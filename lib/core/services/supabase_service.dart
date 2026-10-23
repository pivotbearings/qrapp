import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../auth/auth_controller.dart';

/// Pivot Bearings India - Enterprise Supabase Service
///
/// Features:
/// - Client initialization using only public Anon / Publishable keys
/// - Secure server-side state machine calls (confirm_bearing_in, confirm_bearing_out)
/// - Private Storage uploads into 'verification-images'
/// - Telemetry scan logging
/// - Role authorization helpers (ADMIN vs USER)
class SupabaseService {
  static SupabaseClient? _client;
  static bool _isInitialized = false;

  static SupabaseClient get client {
    if (_client == null) {
      throw StateError(
          'SupabaseService has not been initialized. Call initialize() first.');
    }
    return _client!;
  }

  static bool get isInitialized => _isInitialized;

  /// Initializes Supabase with error recovery if offline or mock keys
  static Future<void> initialize() async {
    try {
      // 1. If Supabase is already initialized, grab instance client
      try {
        _client = Supabase.instance.client;
        _isInitialized = true;
        return;
      } catch (_) {
        // Not yet initialized, continue
      }

      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
      );
      _client = Supabase.instance.client;
      _isInitialized = true;
    } catch (e, stack) {
      debugPrint('SupabaseService.initialize notice: $e\n$stack');
      try {
        _client = Supabase.instance.client;
        _isInitialized = true;
      } catch (_) {
        _isInitialized = false;
      }
    }
  }

  // Auth Helpers
  static User? get currentUser => _isInitialized ? _client?.auth.currentUser : null;
  static String? get currentUserId => currentUser?.id;
  static bool get isAuthenticated => currentUser != null;

  /// Checks whether current user has the 'ADMIN' role in the backend
  static Future<bool> isCurrentUserAdmin() async {
    if (!_isInitialized || currentUser == null) return false;
    try {
      final res = await client
          .from('user_roles')
          .select('role')
          .eq('user_id', currentUser!.id)
          .eq('role', 'ADMIN');
      return res.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Executes authoritative server-side IN confirmation via RPC
  static Future<Map<String, dynamic>?> confirmBearingIn({
    required String bearingId,
    String? verificationImageId,
    String? notes,
  }) async {
    if (!_isInitialized) return null;
    try {
      final isValidUuid = verificationImageId != null &&
          RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(verificationImageId);
      final response = await client.rpc('confirm_bearing_in', params: {
        'p_bearing_id': bearingId,
        'p_verification_image_id': isValidUuid ? verificationImageId : null,
        'p_notes': notes,
      });
      return response as Map<String, dynamic>?;
    } catch (e) {
      rethrow;
    }
  }

  /// Executes authoritative server-side OUT confirmation via RPC
  static Future<Map<String, dynamic>?> confirmBearingOut({
    required String bearingId,
    String? verificationImageId,
    String? notes,
  }) async {
    if (!_isInitialized) return null;
    try {
      final isValidUuid = verificationImageId != null &&
          RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(verificationImageId);
      final response = await client.rpc('confirm_bearing_out', params: {
        'p_bearing_id': bearingId,
        'p_verification_image_id': isValidUuid ? verificationImageId : null,
        'p_notes': notes,
      });
      return response as Map<String, dynamic>?;
    } catch (e) {
      rethrow;
    }
  }

  /// Securely dispatches bearing lifecycle email via Resend RPC
  static Future<Map<String, dynamic>> sendBearingLifecycleEmail({
    required String bearingId,
    required String htmlContent,
    String? subject,
  }) async {
    if (!_isInitialized) {
      return {
        'success': false,
        'error': 'Supabase service is not initialized.',
      };
    }
    try {
      final res = await client.rpc('send_bearing_lifecycle_email', params: {
        'p_bearing_id': bearingId,
        'p_html_content': htmlContent,
        'p_subject': subject ?? 'Pivot Bearings India - Bearing Lifecycle Summary',
      });
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return {'success': true, 'message': 'Email queued successfully via Resend.'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Uploads proof photo into private bucket 'verification-images' under user's folder
  static Future<String?> uploadVerificationImage({
    required Uint8List imageBytes,
    required String filename,
  }) async {
    if (!_isInitialized || currentUser == null) return null;
    try {
      final path = '${currentUser!.id}/$filename';
      await client.storage.from('verification-images').uploadBinary(
            path,
            imageBytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      return path;
    } catch (e) {
      return null;
    }
  }

  /// Logs scan telemetry into scan_records table
  static Future<void> logScanTelemetry({
    required String payload,
    required bool isValid,
    String? qrCodeId,
  }) async {
    if (!_isInitialized) return;
    try {
      await client.from('scan_records').insert({
        'scanned_payload': payload,
        'is_valid': isValid,
        'qr_code_id': qrCodeId,
        'scanned_by': currentUserId,
      });
    } catch (_) {}
  }

  /// Fetches authoritative company settings from Supabase company_settings table
  static Future<Map<String, dynamic>> fetchCompanySettings() async {
    const defaultSettings = {
      'company_name': 'Pivot Bearings India',
      'gst_number': '27AABCU9603R1ZM',
      'plant_location': 'Plant 02 — Chakan Industrial Complex, Pune, Maharashtra',
      'address': 'Plot 42, Phase II, Chakan Industrial Area, Pune 410501',
      'contact_email': 'pivotbearings@gmail.com',
      'contact_phone': '+91 98988 57198',
      'website': 'https://www.pivotbearingsindia.com/',
    };

    if (!_isInitialized) return defaultSettings;
    try {
      final res = await client
          .from('company_settings')
          .select()
          .limit(1)
          .maybeSingle();
      if (res != null) {
        final data = Map<String, dynamic>.from(res);
        data['website'] = 'https://www.pivotbearingsindia.com/';
        data['contact_phone'] = '+91 98988 57198';
        data['contact_email'] = 'pivotbearings@gmail.com';

        // Sync to Supabase in the background if authorized
        client.from('company_settings').update({
          'website': 'https://www.pivotbearingsindia.com/',
          'contact_phone': '+91 98988 57198',
          'contact_email': 'pivotbearings@gmail.com',
        }).eq('id', data['id']).then((_) {}).catchError((_) {});

        return data;
      }
    } catch (_) {}
    return defaultSettings;
  }

  /// Authenticates user with email and password
  static Future<AuthResponse?> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;
    return await client.auth.signInWithPassword(email: email, password: password);
  }

  /// Registers user with initial profile metadata
  static Future<AuthResponse?> signUpWithEmailPassword({
    required String email,
    required String password,
    String? fullName,
    String? companyName,
    String? phone,
    String? facilityCode,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }
    if (!_isInitialized) return null;
    final cleanFac = facilityCode ??
        (companyName != null && companyName.isNotEmpty
            ? 'FAC-${companyName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase()}'
            : 'FAC-REG');
    final safeFac = cleanFac.length > 7 ? cleanFac.substring(0, 7) : cleanFac;

    return await client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName ?? companyName ?? 'Operator',
        'company_name': companyName ?? '',
        'phone': phone ?? '',
        'facility_code': safeFac,
        'role': 'USER',
        'email': email,
      },
    );
  }

  /// Signs current user out and terminates session
  static Future<void> signOut() async {
    if (!_isInitialized) return;
    try {
      await client.auth.signOut();
    } catch (_) {}
  }

  /// Fetches profile information for currently authenticated user
  static Future<Map<String, dynamic>> fetchUserProfile() async {
    final auth = AuthController.instance;
    final currentEmail = currentUser?.email ?? (auth.userEmail?.isNotEmpty == true ? auth.userEmail! : 'operator@company.com');
    final currentName = currentUser?.userMetadata?['full_name'] as String? ?? 
        (auth.userName?.isNotEmpty == true ? auth.userName! : currentEmail.split('@').first);

    // Check offline user registry for richer details
    Map<String, dynamic>? offlineMatch;
    try {
      final offlineUsers = await _loadOfflineUsers();
      offlineMatch = offlineUsers.firstWhere(
        (u) => (u['email'] ?? '').toString().toLowerCase() == currentEmail.toLowerCase(),
        orElse: () => <String, dynamic>{},
      );
    } catch (_) {}

    final defaultProfile = {
      'id': currentUser?.id ?? (offlineMatch?['id'] ?? 'pbi-usr-active'),
      'full_name': offlineMatch?['full_name'] ?? currentName,
      'email': currentEmail,
      'company_name': (offlineMatch?['company_name']?.toString().isNotEmpty == true)
          ? offlineMatch!['company_name']
          : ((currentUser?.userMetadata?['company_name'] as String?)?.isNotEmpty == true
              ? currentUser!.userMetadata!['company_name']
              : (auth.userCompany?.isNotEmpty == true ? auth.userCompany! : 'Industrial Operations')),
      'facility_code': (offlineMatch?['facility_code']?.toString().isNotEmpty == true)
          ? offlineMatch!['facility_code']
          : ((currentUser?.userMetadata?['facility_code'] as String?)?.isNotEmpty == true
              ? currentUser!.userMetadata!['facility_code']
              : 'FAC-REG'),
      'phone': (offlineMatch?['phone']?.toString().isNotEmpty == true)
          ? offlineMatch!['phone']
          : ((currentUser?.userMetadata?['phone'] as String?)?.isNotEmpty == true
              ? currentUser!.userMetadata!['phone']
              : (auth.userPhone?.isNotEmpty == true ? auth.userPhone! : '—')),
      'role': offlineMatch?['role'] ?? auth.role.code,
      'authorised_numbers': (offlineMatch?['authorised_numbers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          (auth.authorisedNumbers.isNotEmpty ? auth.authorisedNumbers : <String>[]),
    };

    if (!_isInitialized || currentUser == null) return defaultProfile;
    try {
      final res = await client
          .from('profiles')
          .select()
          .eq('id', currentUser!.id)
          .maybeSingle();
      if (res != null) {
        final map = Map<String, dynamic>.from(res);
        map['email'] = currentUser!.email ?? map['email'] ?? currentEmail;
        map['full_name'] = map['full_name'] ?? currentName;
        map['company_name'] = (map['company_name']?.toString().isNotEmpty == true)
            ? map['company_name']
            : defaultProfile['company_name'];
        map['facility_code'] = (map['facility_code']?.toString().isNotEmpty == true)
            ? map['facility_code']
            : defaultProfile['facility_code'];
        map['phone'] = (map['phone']?.toString().isNotEmpty == true)
            ? map['phone']
            : defaultProfile['phone'];
        map['authorised_numbers'] = (map['authorised_numbers'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            defaultProfile['authorised_numbers'];
        return map;
      }
    } catch (_) {}
    return defaultProfile;
  }

  /// Fetches historical installation and removal lifecycle events for bearing
  static Future<List<Map<String, dynamic>>> fetchBearingHistory(String bearingId) async {
    if (!_isInitialized) return [];
    try {
      final qr = await client
          .from('qr_codes')
          .select('id')
          .eq('bearing_id', bearingId.trim().toUpperCase())
          .maybeSingle();
      if (qr == null) return [];
      final qrId = qr['id'];

      final events = await client
          .from('bearing_lifecycle_events')
          .select('''
            id,
            event_type,
            server_timestamp,
            notes,
            verification_images (
              id,
              storage_path,
              sha256_hash,
              image_type,
              file_size_bytes
            )
          ''')
          .eq('qr_code_id', qrId)
          .order('server_timestamp', ascending: false);

      return List<Map<String, dynamic>>.from(events);
    } catch (_) {
      return [];
    }
  }

  /// Fetches real-time aggregate dashboard metrics from Supabase database
  static Future<Map<String, dynamic>> fetchAdminDashboardMetrics() async {
    const zeroMetrics = {
      'total_qr_codes': 0,
      'unactivated_qr_codes': 0,
      'currently_in_bearings': 0,
      'currently_out_bearings': 0,
      'active_warranties': 0,
      'expired_warranties': 0,
      'total_scans': 0,
      'invalid_attempts': 0,
      'total_customers': 0,
      'total_batches': 0,
      'flagged_bearings': 0,
    };

    if (!_isInitialized) return zeroMetrics;

    try {
      final res = await client.rpc('get_admin_dashboard_metrics');
      if (res != null) {
        return Map<String, dynamic>.from(res as Map);
      }
    } catch (_) {
      // Fallback: direct table count queries
      try {
        final totalQr = await client.from('qr_codes').count(CountOption.exact);
        final notActivated = await client.from('qr_codes').select('id').eq('current_lifecycle_state', 'NOT_ACTIVATED').count(CountOption.exact);
        final currIn = await client.from('qr_codes').select('id').eq('current_lifecycle_state', 'CURRENTLY_IN').count(CountOption.exact);
        final currOut = await client.from('qr_codes').select('id').eq('current_lifecycle_state', 'CURRENTLY_OUT').count(CountOption.exact);
        final totalScans = await client.from('scan_records').count(CountOption.exact);
        final invalidScans = await client.from('scan_records').select('id').eq('is_valid', false).count(CountOption.exact);
        final customers = await client.from('profiles').count(CountOption.exact);
        final batches = await client.from('qr_batches').count(CountOption.exact);

        return {
          'total_qr_codes': totalQr,
          'unactivated_qr_codes': notActivated,
          'currently_in_bearings': currIn,
          'currently_out_bearings': currOut,
          'active_warranties': currIn,
          'expired_warranties': currOut,
          'total_scans': totalScans,
          'invalid_attempts': invalidScans,
          'total_customers': customers,
          'total_batches': batches,
          'flagged_bearings': 0,
        };
      } catch (_) {}
    }

    return zeroMetrics;
  }

  /// Fetches complete bearing lifecycle details with all installation cycles
  static Future<Map<String, dynamic>?> fetchBearingFullLifecycleDetails(String bearingId) async {
    if (!_isInitialized) return null;
    try {
      final res = await client.rpc('get_bearing_full_lifecycle_details', params: {
        'p_bearing_id': bearingId.trim().toUpperCase(),
      });
      if (res != null) {
        return Map<String, dynamic>.from(res as Map);
      }
    } catch (_) {}
    return null;
  }

  /// Fetches admin audit logs for regulatory and quality compliance
  static Future<List<Map<String, dynamic>>> fetchAdminAuditLogs({int limit = 50, int offset = 0}) async {
    if (!_isInitialized) return [];
    try {
      final res = await client
          .from('admin_audit_logs')
          .select('''
            id,
            admin_id,
            action,
            target_entity,
            target_id,
            old_values,
            new_values,
            ip_address,
            created_at,
            profiles (full_name)
          ''')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      return [];
    }
  }

  /// Fetches invalid scan attempts for security anomaly detection
  static Future<List<Map<String, dynamic>>> fetchInvalidScanAttempts({int limit = 50, int offset = 0}) async {
    if (!_isInitialized) return [];
    try {
      final res = await client
          .from('scan_records')
          .select()
          .eq('is_valid', false)
          .order('scan_timestamp', ascending: false)
          .range(offset, offset + limit - 1);
      return List<Map<String, dynamic>>.from(res);
    } catch (_) {
      return [];
    }
  }

  /// Fetches customer accounts for management
  static Future<List<Map<String, dynamic>>> fetchCustomerProfiles({int limit = 50, int offset = 0, String? query}) async {
    try {
      // 1. Fetch all registered users via role assignment aggregator
      final allUsers = await fetchUsersForRoleAssignment(query: query);
      if (allUsers.isNotEmpty) {
        return allUsers.skip(offset).take(limit).toList();
      }

      // 2. Direct profiles fallback
      if (_isInitialized) {
        var builder = client.from('profiles').select();
        if (query != null && query.trim().isNotEmpty) {
          final q = query.trim();
          builder = builder.or('full_name.ilike.%$q%,company_name.ilike.%$q%,facility_code.ilike.%$q%');
        }
        final res = await builder
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1);
        final list = List<Map<String, dynamic>>.from(res);
        if (list.isNotEmpty) return list;
      }

      // 3. Offline storage fallback
      final offline = await _loadOfflineUsers(query: query);
      return offline.skip(offset).take(limit).toList();
    } catch (_) {
      final offline = await _loadOfflineUsers(query: query);
      return offline.skip(offset).take(limit).toList();
    }
  }

  /// Approves a user account and ensures USER role is assigned
  static Future<bool> approveUser({required String userId, String role = 'USER'}) async {
    if (!_isInitialized) return false;
    try {
      // 1. Try RPC approve_user_by_id
      try {
        await client.rpc('approve_user_by_id', params: {
          'p_user_id': userId,
          'p_role': role,
        });
        return true;
      } catch (_) {}

      // 2. Direct table updates
      await client.from('profiles').update({
        'is_approved': true,
        'is_active': true,
      }).eq('id', userId);

      await client.from('user_roles').upsert({
        'user_id': userId,
        'role': role,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Updates corporate settings in Supabase
  static Future<bool> updateCompanySettings(Map<String, dynamic> settings) async {
    if (!_isInitialized) return false;
    try {
      final current = await client.from('company_settings').select('id').limit(1).maybeSingle();
      if (current != null) {
        await client.from('company_settings').update(settings).eq('id', current['id']);
      } else {
        await client.from('company_settings').insert(settings);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static final Map<String, ({String url, DateTime expiresAt})> _signedUrlCache = {};

  /// Fetches verification images with authorized signed URLs
  static Future<List<Map<String, dynamic>>> fetchVerificationImages({int limit = 20, int offset = 0}) async {
    if (!_isInitialized) return [];
    try {
      final images = await client
          .from('verification_images')
          .select('''
            id,
            qr_code_id,
            storage_path,
            sha256_hash,
            file_size_bytes,
            width,
            height,
            image_type,
            created_at,
            qr_codes (bearing_id)
          ''')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      final List<Map<String, dynamic>> enriched = [];
      for (final img in images) {
        final map = Map<String, dynamic>.from(img);
        final storagePath = map['storage_path']?.toString();
        if (storagePath != null && storagePath.isNotEmpty) {
          // Check if valid cached URL exists
          final cached = _signedUrlCache[storagePath];
          if (cached != null && cached.expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
            map['signed_url'] = cached.url;
          } else {
            try {
              var signedUrl = await client.storage
                  .from('verification-images')
                  .createSignedUrl(storagePath, 3600);
              if (AppConfig.storageCdnUrl != null &&
                  AppConfig.storageCdnUrl!.isNotEmpty) {
                final originUri = Uri.parse(signedUrl);
                final cdnUri = Uri.parse(AppConfig.storageCdnUrl!);
                signedUrl = originUri.replace(
                  scheme: cdnUri.scheme,
                  host: cdnUri.host,
                  port: cdnUri.hasPort ? cdnUri.port : null,
                ).toString();
              }
              _signedUrlCache[storagePath] = (
                url: signedUrl,
                expiresAt: DateTime.now().add(const Duration(seconds: 3500)),
              );
              map['signed_url'] = signedUrl;
            } catch (_) {}
          }
        }
        enriched.add(map);
      }
      return enriched;
    } catch (_) {
      return [];
    }
  }

  /// Fetches registered users and their assigned roles for Admin Role Assignment workstation
  static Future<List<Map<String, dynamic>>> fetchUsersForRoleAssignment({
    String? query,
  }) async {
    if (!_isInitialized) {
      return await _loadOfflineUsers(query: query);
    }

    try {
      // 1. Try authoritative RPC admin_get_all_users
      try {
        final rpcRes = await client.rpc('admin_get_all_users');
        if (rpcRes != null && rpcRes is List && rpcRes.isNotEmpty) {
          var list = List<Map<String, dynamic>>.from(rpcRes);

          // Guarantee that module permissions, authorised numbers, and phone are never omitted
          // if an older version of the RPC stored procedure is active on the Supabase project
          try {
            final profiles = await client.from('profiles').select('id, phone, has_warranty_access, has_track_bearing_access, is_reward_eligible, authorised_numbers');
            final Map<String, Map<String, dynamic>> profMap = {
              for (final p in profiles) (p['id']?.toString() ?? ''): Map<String, dynamic>.from(p)
            };
            for (final u in list) {
              final uid = u['id']?.toString() ?? '';
              final p = profMap[uid];
              if (p != null) {
                u['has_warranty_access'] = p['has_warranty_access'] == true;
                u['has_track_bearing_access'] = p['has_track_bearing_access'] == true;
                u['is_reward_eligible'] = p['is_reward_eligible'] != false;
                if (p['authorised_numbers'] != null) {
                  u['authorised_numbers'] = (p['authorised_numbers'] as List<dynamic>?)
                      ?.map((e) => e.toString())
                      .toList() ?? [];
                }
                if (p['phone'] != null && (u['phone'] == null || u['phone'] == '—' || u['phone'].toString().trim().isEmpty)) {
                  u['phone'] = p['phone'];
                }
              }
            }
          } catch (e) {
            debugPrint('Notice: profiles merge in fetchUsersForRoleAssignment: $e');
          }

          if (query != null && query.trim().isNotEmpty) {
            final q = query.trim().toLowerCase();
            list = list.where((u) {
              final email = (u['email'] ?? '').toString().toLowerCase();
              final name = (u['full_name'] ?? '').toString().toLowerCase();
              final comp = (u['company_name'] ?? '').toString().toLowerCase();
              return email.contains(q) || name.contains(q) || comp.contains(q);
            }).toList();
          }
          return list;
        }
      } catch (_) {}

      // 2. Direct table fallback: profiles joined with user_roles
      var profilesBuilder = client.from('profiles').select();
      if (query != null && query.trim().isNotEmpty) {
        final q = query.trim();
        profilesBuilder = profilesBuilder.or('full_name.ilike.%$q%,company_name.ilike.%$q%,email.ilike.%$q%');
      }
      final profiles = await profilesBuilder.order('created_at', ascending: false);

      Map<String, String> rolesMap = {};
      try {
        final rolesRes = await client.from('user_roles').select('user_id, role');
        for (final r in rolesRes) {
          final uid = r['user_id']?.toString();
          final role = r['role']?.toString();
          if (uid != null && role != null) {
            rolesMap[uid] = role;
          }
        }
      } catch (_) {}

      final merged = <Map<String, dynamic>>[];
      for (final p in profiles) {
        final uid = p['id']?.toString() ?? '';
        final role = rolesMap[uid] ?? 'USER';
        merged.add({
          'id': uid,
          'email': p['email'] ?? '—',
          'full_name': p['full_name'] ?? 'Operator',
          'company_name': p['company_name'] ?? '',
          'facility_code': p['facility_code'] ?? '',
          'phone': p['phone'] ?? '—',
          'role': role,
          'is_approved': p['is_approved'] == true,
          'is_active': p['is_active'] != false,
          'has_warranty_access': p['has_warranty_access'] == true,
          'has_track_bearing_access': p['has_track_bearing_access'] == true,
          'is_reward_eligible': p['is_reward_eligible'] != false,
          'authorised_numbers': (p['authorised_numbers'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [],
          'created_at': p['created_at'],
        });
      }

      if (merged.isNotEmpty) {
        return merged;
      }
      return await _loadOfflineUsers(query: query);
    } catch (e) {
      debugPrint('Notice: Supabase fetchUsersForRoleAssignment fallback: $e');
      return await _loadOfflineUsers(query: query);
    }
  }

  /// Updates user role and approval clearance status (Admin only)
  static Future<bool> updateUserRoleAndClearance({
    required String userId,
    required String role,
    required bool isApproved,
    String? email,
  }) async {
    final normalizedRole = role.toUpperCase().trim();

    if (_isInitialized) {
      // 1. Try authoritative RPC
      try {
        await client.rpc('admin_update_user_role_and_clearance', params: {
          'p_target_user_id': userId,
          'p_role': normalizedRole,
          'p_approved': isApproved,
        });
        await _updateOfflineUser(userId: userId, email: email, role: normalizedRole, isApproved: isApproved);
        return true;
      } catch (_) {}

      // 2. Direct table update fallback
      try {
        await client.from('profiles').update({
          'is_approved': isApproved,
          'is_active': isApproved,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);

        await client.from('user_roles').upsert({
          'user_id': userId,
          'role': normalizedRole,
          'assigned_at': DateTime.now().toIso8601String(),
        });

        await _updateOfflineUser(userId: userId, email: email, role: normalizedRole, isApproved: isApproved);
        return true;
      } catch (e) {
        debugPrint('Notice: direct table update fallback: $e');
      }
    }

    await _updateOfflineUser(userId: userId, email: email, role: normalizedRole, isApproved: isApproved);
    return true;
  }

  /// Updates user module permissions (Warranty Module and Track Your Bearing Module)
  static Future<bool> updateUserModulePermissions({
    required String userId,
    required bool hasWarranty,
    required bool hasTrackBearing,
    String? email,
  }) async {
    if (_isInitialized) {
      // 1. Try authoritative RPC admin_update_user_module_permissions
      try {
        await client.rpc('admin_update_user_module_permissions', params: {
          'p_target_user_id': userId,
          'p_has_warranty': hasWarranty,
          'p_has_track_bearing': hasTrackBearing,
        });
        await _updateOfflineUserModulePermissions(
          userId: userId,
          email: email,
          hasWarranty: hasWarranty,
          hasTrackBearing: hasTrackBearing,
        );
        return true;
      } catch (_) {}

      // 2. Direct table update fallback
      try {
        await client.from('profiles').update({
          'has_warranty_access': hasWarranty,
          'has_track_bearing_access': hasTrackBearing,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);

        await _updateOfflineUserModulePermissions(
          userId: userId,
          email: email,
          hasWarranty: hasWarranty,
          hasTrackBearing: hasTrackBearing,
        );
        return true;
      } catch (e) {
        debugPrint('Notice: direct profiles module permissions update: $e');
      }
    }

    await _updateOfflineUserModulePermissions(
      userId: userId,
      email: email,
      hasWarranty: hasWarranty,
      hasTrackBearing: hasTrackBearing,
    );
    return true;
  }

  /// Updates user reward points eligibility (Toggle ON/OFF from Customers page)
  static Future<bool> updateUserRewardEligibility({
    required String userId,
    required bool isEligible,
    String? email,
  }) async {
    if (_isInitialized) {
      // 1. Try authoritative RPC admin_update_user_reward_eligibility
      try {
        await client.rpc('admin_update_user_reward_eligibility', params: {
          'p_target_user_id': userId,
          'p_is_eligible': isEligible,
        });
        await _updateOfflineUserRewardEligibility(
          userId: userId,
          email: email,
          isEligible: isEligible,
        );
        return true;
      } catch (_) {}

      // 2. Direct table update fallback
      try {
        await client.from('profiles').update({
          'is_reward_eligible': isEligible,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);

        try {
          await client.from('user_reward_wallets').update({
            'is_frozen': !isEligible,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('user_id', userId);
        } catch (_) {}

        await _updateOfflineUserRewardEligibility(
          userId: userId,
          email: email,
          isEligible: isEligible,
        );
        return true;
      } catch (e) {
        debugPrint('Notice: direct profiles is_reward_eligible update: $e');
      }
    }

    await _updateOfflineUserRewardEligibility(
      userId: userId,
      email: email,
      isEligible: isEligible,
    );
    return true;
  }

  static Future<void> _updateOfflineUserRewardEligibility({
    required String userId,
    String? email,
    required bool isEligible,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (email != null && email.isNotEmpty) {
        await prefs.setBool('offline_reward_eligible_$email', isEligible);
      }

      final raw = prefs.getString('registered_offline_users_json');
      List<Map<String, dynamic>> users = [];
      if (raw != null) {
        try {
          users = List<Map<String, dynamic>>.from(jsonDecode(raw));
        } catch (_) {}
      }

      for (final u in users) {
        if (u['id'] == userId || (email != null && u['email'] == email)) {
          u['is_reward_eligible'] = isEligible;
          break;
        }
      }

      await prefs.setString('registered_offline_users_json', jsonEncode(users));
    } catch (_) {}
  }

  /// Updates user's configured authorised person numbers (up to 10 numbers)
  static Future<bool> updateUserAuthorisedNumbers({
    required String userId,
    required List<String> numbers,
    String? email,
  }) async {
    final cleanNumbers = numbers
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .take(10)
        .toList();

    if (_isInitialized) {
      // 1. Authoritative RPC admin_update_user_authorised_numbers
      try {
        await client.rpc('admin_update_user_authorised_numbers', params: {
          'p_target_user_id': userId,
          'p_numbers': cleanNumbers,
        });
      } catch (_) {}

      // 2. Direct table update guarantee: sync both authorised_numbers and phone
      try {
        final primaryPhone = cleanNumbers.isNotEmpty ? cleanNumbers.first : null;
        final updateMap = <String, dynamic>{
          'authorised_numbers': cleanNumbers,
          'updated_at': DateTime.now().toIso8601String(),
        };
        if (primaryPhone != null) {
          updateMap['phone'] = primaryPhone;
        }
        await client.from('profiles').update(updateMap).eq('id', userId);
      } catch (e) {
        debugPrint('Notice: direct profiles authorised_numbers update: $e');
      }

      await _updateOfflineUserAuthorisedNumbers(
        userId: userId,
        email: email,
        numbers: cleanNumbers,
      );
      return true;
    }

    await _updateOfflineUserAuthorisedNumbers(
      userId: userId,
      email: email,
      numbers: cleanNumbers,
    );
    return true;
  }

  static Future<void> _updateOfflineUserAuthorisedNumbers({
    required String userId,
    String? email,
    required List<String> numbers,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (email != null && email.isNotEmpty) {
        await prefs.setStringList('offline_authorised_numbers_$email', numbers);
      }

      final raw = prefs.getString('registered_offline_users_json');
      List<Map<String, dynamic>> users = [];
      if (raw != null) {
        try {
          users = List<Map<String, dynamic>>.from(jsonDecode(raw));
        } catch (_) {}
      }

      for (final u in users) {
        if (u['id'] == userId || (email != null && u['email'] == email)) {
          u['authorised_numbers'] = numbers;
          break;
        }
      }

      await prefs.setString('registered_offline_users_json', jsonEncode(users));
    } catch (_) {}
  }

  static Future<void> _updateOfflineUserModulePermissions({
    required String userId,
    String? email,
    required bool hasWarranty,
    required bool hasTrackBearing,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (email != null && email.isNotEmpty) {
        await prefs.setBool('offline_warranty_$email', hasWarranty);
        await prefs.setBool('offline_track_$email', hasTrackBearing);
      }

      final raw = prefs.getString('registered_offline_users_json');
      List<Map<String, dynamic>> users = [];
      if (raw != null) {
        try {
          users = List<Map<String, dynamic>>.from(jsonDecode(raw));
        } catch (_) {}
      }

      for (final u in users) {
        if (u['id'] == userId || (email != null && u['email'] == email)) {
          u['has_warranty_access'] = hasWarranty;
          u['has_track_bearing_access'] = hasTrackBearing;
          break;
        }
      }

      await prefs.setString('registered_offline_users_json', jsonEncode(users));
    } catch (_) {}
  }

  /// Loads registered accounts for offline and development mode
  static Future<List<Map<String, dynamic>>> _loadOfflineUsers({String? query}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('registered_offline_users_json');
      List<Map<String, dynamic>> users = [];
      if (raw != null) {
        try {
          users = List<Map<String, dynamic>>.from(jsonDecode(raw));
        } catch (_) {}
      }

      // Default baseline accounts if none exist
      if (users.isEmpty) {
        users = [
          {
            'id': 'pbi-usr-admin-01',
            'email': 'abc@gmail.com',
            'full_name': 'Chief System Administrator',
            'company_name': 'Pivot Bearings India Ltd',
            'facility_code': 'PBI-HQ-CHAKAN',
            'role': 'ADMIN',
            'is_approved': true,
            'is_active': true,
            'has_warranty_access': true,
            'has_track_bearing_access': true,
            'authorised_numbers': ['+919898857198'],
            'created_at': DateTime.now().subtract(const Duration(days: 30)).toIso8601String(),
          },
          {
            'id': 'pbi-usr-field-02',
            'email': 'user@gmail.com',
            'full_name': 'Certified Field Inspector',
            'company_name': 'Apex Engineering Facility',
            'facility_code': 'APX-IND-04',
            'role': 'USER',
            'is_approved': false,
            'is_active': true,
            'has_warranty_access': false,
            'has_track_bearing_access': false,
            'authorised_numbers': <String>[],
            'created_at': DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
          },
        ];
        await prefs.setString('registered_offline_users_json', jsonEncode(users));
      }

      // Sync with any individual offline flags
      for (final u in users) {
        final email = u['email']?.toString();
        if (email != null) {
          final savedAppr = prefs.getBool('offline_approved_$email');
          if (savedAppr != null) {
            u['is_approved'] = savedAppr;
          }
          final savedRole = prefs.getString('offline_role_$email');
          if (savedRole != null) {
            u['role'] = savedRole;
          }
          final savedWarranty = prefs.getBool('offline_warranty_$email');
          if (savedWarranty != null) {
            u['has_warranty_access'] = savedWarranty;
          } else {
            u['has_warranty_access'] = (u['has_warranty_access'] == true);
          }
          final savedTrack = prefs.getBool('offline_track_$email');
          if (savedTrack != null) {
            u['has_track_bearing_access'] = savedTrack;
          } else {
            u['has_track_bearing_access'] = (u['has_track_bearing_access'] == true);
          }
          final savedNumbers = prefs.getStringList('offline_authorised_numbers_$email');
          if (savedNumbers != null) {
            u['authorised_numbers'] = savedNumbers;
          } else {
            u['authorised_numbers'] = (u['authorised_numbers'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                <String>[];
          }
          final savedRewardEligible = prefs.getBool('offline_reward_eligible_$email');
          if (savedRewardEligible != null) {
            u['is_reward_eligible'] = savedRewardEligible;
          } else {
            u['is_reward_eligible'] = (u['is_reward_eligible'] != false);
          }
        }
      }

      if (query != null && query.trim().isNotEmpty) {
        final q = query.trim().toLowerCase();
        users = users.where((u) {
          final email = (u['email'] ?? '').toString().toLowerCase();
          final name = (u['full_name'] ?? '').toString().toLowerCase();
          final comp = (u['company_name'] ?? '').toString().toLowerCase();
          return email.contains(q) || name.contains(q) || comp.contains(q);
        }).toList();
      }

      return users;
    } catch (_) {
      return [];
    }
  }

  /// Updates offline cache record
  static Future<void> _updateOfflineUser({
    required String userId,
    String? email,
    required String role,
    required bool isApproved,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (email != null && email.isNotEmpty) {
        await prefs.setBool('offline_approved_$email', isApproved);
        await prefs.setString('offline_role_$email', role);
      }

      final raw = prefs.getString('registered_offline_users_json');
      List<Map<String, dynamic>> users = [];
      if (raw != null) {
        try {
          users = List<Map<String, dynamic>>.from(jsonDecode(raw));
        } catch (_) {}
      }

      bool updated = false;
      for (final u in users) {
        if (u['id'] == userId || (email != null && u['email'] == email)) {
          u['role'] = role;
          u['is_approved'] = isApproved;
          updated = true;
          break;
        }
      }

      if (!updated && email != null) {
        users.insert(0, {
          'id': userId,
          'email': email,
          'full_name': email.split('@').first,
          'company_name': 'Industrial Facility',
          'facility_code': 'FAC-01',
          'role': role,
          'is_approved': isApproved,
          'is_active': true,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      await prefs.setString('registered_offline_users_json', jsonEncode(users));
    } catch (_) {}
  }
}

/// Configuration model for the customer home advertisement banner
class AdBannerConfig {
  final String image;
  final String targetUrl;
  final bool isActive;
  final String format;
  final String fitMode; // 'contain' or 'cover'

  const AdBannerConfig({
    required this.image,
    required this.targetUrl,
    required this.isActive,
    this.format = 'webp',
    this.fitMode = 'contain',
  });

  /// Authoritative default configuration bundled with app
  factory AdBannerConfig.defaultConfig() {
    return const AdBannerConfig(
      image: 'assets/ad_banner.webp',
      targetUrl: 'https://www.pivotbearingsindia.com/',
      isActive: true,
      format: 'webp',
      fitMode: 'contain',
    );
  }

  Map<String, dynamic> toJson() => {
        'image': image,
        'target_url': targetUrl,
        'is_active': isActive,
        'format': format,
        'fit_mode': fitMode,
      };

  factory AdBannerConfig.fromJson(Map<String, dynamic> json) {
    return AdBannerConfig(
      image: (json['image'] ?? json['imageUrl'] ?? 'assets/ad_banner.webp').toString(),
      targetUrl: (json['target_url'] ?? json['targetUrl'] ?? 'https://www.pivotbearingsindia.com/').toString(),
      isActive: json['is_active'] is bool
          ? json['is_active'] as bool
          : (json['isActive'] is bool ? json['isActive'] as bool : true),
      format: (json['format'] ?? 'webp').toString(),
      fitMode: (json['fit_mode'] ?? json['fitMode'] ?? 'contain').toString(),
    );
  }

  AdBannerConfig copyWith({
    String? image,
    String? targetUrl,
    bool? isActive,
    String? format,
    String? fitMode,
  }) {
    return AdBannerConfig(
      image: image ?? this.image,
      targetUrl: targetUrl ?? this.targetUrl,
      isActive: isActive ?? this.isActive,
      format: format ?? this.format,
      fitMode: fitMode ?? this.fitMode,
    );
  }
}

/// Service managing advertisement banner synchronization and caching
class AdBannerService {
  static const String _prefKey = 'pivot_home_ad_banner_v1';
  static const String _supabaseKey = 'home_ad_banner';

  static AdBannerConfig _memoryCache = AdBannerConfig.defaultConfig();
  static bool _hasLoaded = false;

  /// In-memory cache for fast, non-blocking UI reads
  static AdBannerConfig get currentConfig => _memoryCache;

  /// Validates whether a byte stream is true WebP container format (RIFF....WEBP)
  static bool isWebPBytes(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final isRiff = bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46;
    final isWebP = bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50;
    return isRiff && isWebP;
  }

  /// Fetches the banner configuration. Reads local disk cache instantly,
  /// then asynchronously updates from Supabase `app_settings`.
  static Future<AdBannerConfig> fetchBannerConfig({bool forceRefresh = false}) async {
    // 1. Read from SharedPreferences if not already in memory
    if (!_hasLoaded || forceRefresh) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefKey);
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          _memoryCache = AdBannerConfig.fromJson(decoded);
          _hasLoaded = true;
        }
      } catch (e) {
        debugPrint('AdBannerService cache read error: $e');
      }
    }

    // 2. Fetch authoritative configuration from Supabase
    try {
      if (SupabaseService.isInitialized) {
        final client = SupabaseService.client;
        final res = await client
            .from('app_settings')
            .select('setting_value')
            .eq('setting_key', _supabaseKey)
            .maybeSingle();

        if (res != null && res['setting_value'] != null) {
          final val = res['setting_value'];
          final Map<String, dynamic> configMap;
          if (val is Map<String, dynamic>) {
            configMap = val;
          } else if (val is String) {
            configMap = jsonDecode(val) as Map<String, dynamic>;
          } else {
            configMap = Map<String, dynamic>.from(val as Map);
          }

          _memoryCache = AdBannerConfig.fromJson(configMap);
          _hasLoaded = true;

          // Save fresh version to local disk cache
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefKey, jsonEncode(_memoryCache.toJson()));
        }
      }
    } catch (e) {
      debugPrint('AdBannerService remote fetch error: $e');
    }

    return _memoryCache;
  }

  /// Saves a new banner configuration to both local storage and Supabase
  static Future<bool> saveBannerConfig(AdBannerConfig config) async {
    _memoryCache = config;
    _hasLoaded = true;

    // 1. Immediately persist to local device storage
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(config.toJson()));
    } catch (e) {
      debugPrint('AdBannerService local save error: $e');
    }

    // 2. Persist to Supabase app_settings table
    try {
      if (SupabaseService.isInitialized) {
        final client = SupabaseService.client;
        final existing = await client
            .from('app_settings')
            .select('id')
            .eq('setting_key', _supabaseKey)
            .maybeSingle();

        if (existing != null) {
          await client.from('app_settings').update({
            'setting_value': config.toJson(),
            'is_public': true,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', existing['id']);
        } else {
          await client.from('app_settings').insert({
            'setting_key': _supabaseKey,
            'setting_value': config.toJson(),
            'description': 'Customer Home Screen Advertisement WebP Banner Configuration',
            'is_public': true,
          });
        }
        return true;
      }
    } catch (e) {
      debugPrint('AdBannerService remote save error: $e');
    }

    return true;
  }

  /// Resets banner back to the default bundled Pivot Bearings WebP advertisement
  static Future<bool> resetToDefault() async {
    return await saveBannerConfig(AdBannerConfig.defaultConfig());
  }
}

