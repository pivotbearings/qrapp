import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../domain/models/bearing_authentication_result.dart';
import '../../../qr_generation/domain/services/bearing_encryption_key_service.dart';

import '../../../rewards/data/services/reward_service.dart';

/// Pivot Bearings India - Authoritative Bearing Authentication Service
///
/// Ensures accurate, consistent scan tracking across users and devices:
/// 1. Authoritative Supabase RPC `authenticate_bearing_qr` execution
/// 2. Direct table fallback with atomic scan count increment
/// 3. Offline persistent storage fallback for testing & local resilience
/// 4. Strict enforcement: Never identifies an unregistered code as genuine.
/// 5. Automatically claims 1st-scan reward points across modules.
class BearingAuthenticationService {
  static const String _localScanCountPrefix = 'pbi_scan_count_';
  static const String _localFirstScanPrefix = 'pbi_first_scan_';
  static const String _deviceScannedPrefix = 'pbi_device_scanned_';

  /// Retrieves or generates a persistent device fingerprint to differentiate between
  /// scans on the same device vs. scans on new/different devices.
  static Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('pbi_device_fingerprint_id');
    if (id == null || id.isEmpty) {
      id = 'DEV-${DateTime.now().millisecondsSinceEpoch}-${(1000 + (DateTime.now().microsecond % 9000))}';
      await prefs.setString('pbi_device_fingerprint_id', id);
    }
    return id;
  }

  /// Primary Authentication Pipeline with 1st-Scan Reward Hook
  static Future<BearingAuthenticationResult> authenticateBearing(String rawPayload) async {
    final res = await _authenticateBearingInternal(rawPayload);
    if (res.isAuthentic && !res.isAlreadyOut) {
      try {
        final reward = await RewardService.claimBearingScanReward(
          rawPayloadOrId: rawPayload,
          sourceModule: 'AUTHENTICATE_BEARING',
        );
        return res.copyWithReward(reward);
      } catch (e) {
        debugPrint('Authentication reward hook error: $e');
      }
    }
    return res;
  }

  static Future<BearingAuthenticationResult> _authenticateBearingInternal(String rawPayload) async {
    final cleanPayload = rawPayload.trim();
    if (cleanPayload.isEmpty) {
      return BearingAuthenticationResult.invalid(
        rawPayload: rawPayload,
        message: 'Empty QR code payload.',
      );
    }

    final bearingId = _extractBearingId(cleanPayload);
    final prefs = await SharedPreferences.getInstance();
    final deviceId = await _getOrCreateDeviceId();

    // Fast-path decommissioned check: if bearing marked out, refuse authentication
    final isPermanentlyOut = prefs.getBool('pbi_bearing_permanently_out_$bearingId') == true ||
        prefs.getString('pbi_track_state_$bearingId') == 'FINAL_OUT';
    if (isPermanentlyOut) {
      return BearingAuthenticationResult.alreadyOut(
        bearingId: bearingId,
        rawPayload: cleanPayload,
        message: 'bearing marked as out, cant scan again.',
      );
    }

    // 1. Attempt authoritative Supabase RPC call
    if (SupabaseService.isInitialized) {
      try {
        final dynamic res = await SupabaseService.client.rpc(
          'authenticate_bearing_qr',
          params: {
            'p_scanned_payload': cleanPayload,
            'p_device_info': deviceId,
          },
        );

        if (res != null && res is Map) {
          final data = Map<String, dynamic>.from(res);
          // Mark this device as having authenticated this bearing
          await prefs.setBool('$_deviceScannedPrefix$bearingId', true);
          return BearingAuthenticationResult.fromJson(data, rawPayload: cleanPayload);
        }
      } catch (e) {
        debugPrint('Supabase RPC authenticate_bearing_qr error, attempting fallback: $e');
        // Fall back to direct query or offline mode
      }

      // 2. Direct Supabase Query Fallback (if RPC migration is pending)
      try {
        final row = await SupabaseService.client
            .from('qr_codes')
            .select('''
              id,
              bearing_id,
              model_number,
              current_lifecycle_state,
              first_in_timestamp,
              warranty_expiry_timestamp,
              is_flagged,
              flag_reason,
              scan_count,
              first_scanned_at,
              qr_batches (batch_code, plant_location),
              warranty_plans:assigned_warranty_plan_id (title, duration_months)
            ''')
            .or('bearing_id.eq.$bearingId,payload_value.eq.$cleanPayload')
            .maybeSingle();

        if (row != null) {
          final qrId = row['id']?.toString();
          final lifecycleState = row['current_lifecycle_state']?.toString() ?? 'NOT_ACTIVATED';

          // If bearing was marked OUT, it cannot be scanned for authentication
          if (lifecycleState == 'FINAL_OUT' || lifecycleState == 'CURRENTLY_OUT' || lifecycleState == 'DECOMMISSIONED') {
            return BearingAuthenticationResult.alreadyOut(
              bearingId: row['bearing_id']?.toString() ?? bearingId,
              rawPayload: cleanPayload,
              message: 'bearing marked as out, cant scan again.',
            );
          }

          final currentUserId = SupabaseService.currentUserId;
          final currentEmail = AuthController.instance.userEmail?.trim().toLowerCase() ?? 'anonymous';
          final scannedUsersKey = 'pbi_scanned_users_$bearingId';
          final scannedUsersList = prefs.getStringList(scannedUsersKey) ?? <String>[];
          final userIdentifier = currentUserId ?? currentEmail;

          // Check if this user/account already authenticated this bearing
          bool alreadyScannedByUser = scannedUsersList.contains(userIdentifier);

          // If not in local cache, verify against scan_records in Supabase
          if (!alreadyScannedByUser && qrId != null && currentUserId != null) {
            try {
              final priorScans = await SupabaseService.client
                  .from('scan_records')
                  .select('id')
                  .eq('qr_code_id', qrId)
                  .eq('scanned_by', currentUserId)
                  .eq('is_valid', true)
                  .limit(1);
              if (priorScans.isNotEmpty) {
                alreadyScannedByUser = true;
              }
            } catch (_) {}
          }

          final dbScanCount = (row['scan_count'] as num?)?.toInt() ?? 0;
          final localCount = prefs.getInt('$_localScanCountPrefix$bearingId') ?? 0;
          final prevScanCount = dbScanCount > 0 ? dbScanCount : localCount;
          
          // 1 email = 1 scan count: only increment if scanned from a new/different email/user
          final int totalScans;
          if (alreadyScannedByUser) {
            totalScans = prevScanCount > 0 ? prevScanCount : 1;
          } else {
            totalScans = prevScanCount + 1;
            scannedUsersList.add(userIdentifier);
            await prefs.setStringList(scannedUsersKey, scannedUsersList);
          }

          final nowIso = DateTime.now().toIso8601String();

          await prefs.setBool('$_deviceScannedPrefix$bearingId', true);
          await prefs.setInt('$_localScanCountPrefix$bearingId', totalScans);

          // Update qr_codes scan_count and log scan telemetry
          if (qrId != null) {
            if (!alreadyScannedByUser) {
              SupabaseService.client.from('qr_codes').update({
                'scan_count': totalScans,
                'last_scanned_at': nowIso,
              }).eq('id', qrId).then((_) {}).catchError((_) {});
            }

            // Log telemetry into scan_records
            SupabaseService.client.from('scan_records').insert({
              'qr_code_id': qrId,
              'scanned_payload': cleanPayload,
              'is_valid': true,
              'scanned_by': currentUserId,
              'device_info': deviceId,
              'scan_timestamp': nowIso,
            }).then((_) {}).catchError((_) {});
          }

          final batch = row['qr_batches'] as Map<String, dynamic>?;
          final plan = row['warranty_plans'] as Map<String, dynamic>?;
          final dur = (plan?['duration_months'] as num?)?.toInt() ?? 6;

          return BearingAuthenticationResult(
            isAuthentic: true,
            previousScanCount: prevScanCount,
            totalScanCount: totalScans,
            bearingId: row['bearing_id']?.toString() ?? bearingId,
            modelNumber: row['model_number']?.toString() ?? 'PBI-6204-ZZ',
            batchCode: batch?['batch_code']?.toString() ?? 'BATCH-ACTIVE',
            plantLocation: batch?['plant_location']?.toString() ?? 'Plant 02 — Chakan Industrial Complex',
            warrantyPlanTitle: plan?['title']?.toString() ?? '$dur Months Warranty',
            warrantyDurationMonths: dur,
            currentLifecycleState: lifecycleState,
            firstScannedAt: row['first_scanned_at'] != null
                ? DateTime.tryParse(row['first_scanned_at'].toString())
                : DateTime.now(),
            lastScannedAt: DateTime.now(),
            isFlagged: row['is_flagged'] == true,
            flagReason: row['flag_reason']?.toString(),
            rawPayload: cleanPayload,
          );
        } else {
          // Unregistered code: log invalid telemetry
          SupabaseService.client.from('scan_records').insert({
            'scanned_payload': cleanPayload,
            'is_valid': false,
            'scanned_by': SupabaseService.currentUserId,
            'device_info': deviceId,
            'scan_timestamp': DateTime.now().toIso8601String(),
          }).then((_) {}).catchError((_) {});

          return BearingAuthenticationResult.invalid(
            rawPayload: cleanPayload,
            scannedId: bearingId,
            message: 'Bearing Authenticity Could Not Be Verified',
          );
        }
      } catch (e) {
        debugPrint('Direct Supabase verification error, falling back to local registry: $e');
      }
    }

    // 3. Local Registry Fallback (Offline / Development Mode)
    return await _localVerify(cleanPayload);
  }

  /// Extracts bearing identifier from URL or raw payload
  static String _extractBearingId(String payload) {
    var id = payload.trim();
    if (id.contains('/pbi/')) {
      final parts = id.split('/pbi/');
      if (parts.length > 1) {
        id = parts[1].split('?').first.split('&').first;
      }
    } else if (id.contains('://')) {
      final uri = Uri.tryParse(id);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        id = uri.pathSegments.last.split('?').first;
      }
    }
    // If it's a 12-char randomized token, preserve exact case
    if (RegExp(r'^[A-Za-z0-9@$#\[\]\-\*]{12}$').hasMatch(id)) {
      return id.trim();
    }
    return id.toUpperCase().trim();
  }

  /// Local validation with persistent unique device scan tracking (SharedPreferences)
  static Future<BearingAuthenticationResult> _localVerify(String cleanPayload) async {
    final bearingId = _extractBearingId(cleanPayload);

    // Validate identifier format
    final isKnownFormat = BearingEncryptionKeyService.isValidKeyOrId(bearingId) ||
        RegExp(r'^(PB-[0-9]{4}-[A-Z0-9]{2}|PBI-SEC-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}|(PBI|PB)(-[A-Z0-9]{3,8}){2,5})$', caseSensitive: false).hasMatch(bearingId);

    // List of registered seed bearings
    final knownRegisteredIds = {
      'PB-9402-XJ': {
        'model': 'PBI-6204-ZZ',
        'batch': 'BATCH-2026-OCT-A',
        'plant': 'Plant 02 — Chakan Industrial Complex',
        'warranty': '6 Months Heavy Duty Warranty',
        'duration': 6,
      },
      'PB-8812-KR': {
        'model': 'PBI-6309-2RS',
        'batch': 'BATCH-2026-OCT-A',
        'plant': 'Plant 02 — Chakan Industrial Complex',
        'warranty': '12 Months Industrial Warranty',
        'duration': 12,
      },
      'PB-1044-ZN': {
        'model': 'PBI-22216-E',
        'batch': 'BATCH-2026-SEP-B',
        'plant': 'Plant 01 — Bhosari Precision Plant',
        'warranty': '24 Months Extended Mining Warranty',
        'duration': 24,
      },
    };

    final isKnownSeed = knownRegisteredIds.containsKey(bearingId);
    final isGenuineKey = BearingEncryptionKeyService.verifyTamperProofChecksum(bearingId);

    // If neither a valid seed bearing nor a verified cryptographic key, mark INVALID!
    if (!isKnownFormat || (!isKnownSeed && !isGenuineKey)) {
      return BearingAuthenticationResult.invalid(
        rawPayload: cleanPayload,
        scannedId: bearingId,
        message: 'Bearing Authenticity Could Not Be Verified',
      );
    }

    // Authentic bearing resolved: Retrieve persistent scan count
    final prefs = await SharedPreferences.getInstance();

    // Terminal guard: if bearing marked out, refuse authentication
    final isPermanentlyOut = prefs.getBool('pbi_bearing_permanently_out_$bearingId') == true ||
        prefs.getString('pbi_track_state_$bearingId') == 'FINAL_OUT';
    if (isPermanentlyOut) {
      return BearingAuthenticationResult.alreadyOut(
        bearingId: bearingId,
        rawPayload: cleanPayload,
        message: 'bearing marked as out, cant scan again.',
      );
    }

    final countKey = '$_localScanCountPrefix$bearingId';
    final firstScanKey = '$_localFirstScanPrefix$bearingId';
    final scannedUsersKey = 'pbi_scanned_users_$bearingId';
    final currentEmail = AuthController.instance.userEmail?.trim().toLowerCase() ?? 'anonymous';
    final currentUserId = SupabaseService.currentUserId;
    final userIdentifier = currentUserId ?? currentEmail;

    final scannedUsersList = prefs.getStringList(scannedUsersKey) ?? <String>[];
    final bool alreadyScannedByUser = scannedUsersList.contains(userIdentifier);

    final previousScans = prefs.getInt(countKey) ?? 0;
    final int totalScans;
    if (alreadyScannedByUser) {
      totalScans = previousScans > 0 ? previousScans : 1;
    } else {
      totalScans = previousScans + 1;
      scannedUsersList.add(userIdentifier);
      await prefs.setStringList(scannedUsersKey, scannedUsersList);
    }

    await prefs.setInt(countKey, totalScans);
    await prefs.setBool('$_deviceScannedPrefix$bearingId', true);

    DateTime firstScannedAt;
    final storedFirstScan = prefs.getString(firstScanKey);
    if (storedFirstScan != null) {
      firstScannedAt = DateTime.tryParse(storedFirstScan) ?? DateTime.now();
    } else {
      firstScannedAt = DateTime.now();
      await prefs.setString(firstScanKey, firstScannedAt.toIso8601String());
    }

    // Metadata extraction
    String model = 'PBI-6204-ZZ';
    String batch = 'BATCH-2026-OCT-A';
    String plant = 'Plant 02 — Chakan Industrial Complex';
    String warrantyTitle = 'Standard Factory Warranty';
    int durationMonths = 6;

    if (isKnownSeed) {
      final info = knownRegisteredIds[bearingId]!;
      model = info['model'] as String;
      batch = info['batch'] as String;
      plant = info['plant'] as String;
      warrantyTitle = info['warranty'] as String;
      durationMonths = info['duration'] as int;
    } else if (isGenuineKey) {
      final decoded = BearingEncryptionKeyService.decodeKey(bearingId);
      final modelTok = decoded['model_token'] ?? '6204';
      model = 'PBI-$modelTok-ZZ';
      batch = 'BATCH-CRYPTO-V2';
      plant = 'Plant 02 — Chakan Industrial Complex';
      warrantyTitle = 'Tamper-Proof Assurance Warranty';
      durationMonths = 12;
    }

    return BearingAuthenticationResult(
      isAuthentic: true,
      previousScanCount: previousScans,
      totalScanCount: totalScans,
      bearingId: bearingId,
      modelNumber: model,
      batchCode: batch,
      plantLocation: plant,
      warrantyPlanTitle: warrantyTitle,
      warrantyDurationMonths: durationMonths,
      currentLifecycleState: 'NOT_ACTIVATED',
      firstScannedAt: firstScannedAt,
      lastScannedAt: DateTime.now(),
      rawPayload: cleanPayload,
    );
  }

  /// Reset local scan count for testing purposes
  static Future<void> resetLocalScanCount(String bearingId) async {
    final prefs = await SharedPreferences.getInstance();
    final id = _extractBearingId(bearingId);
    await prefs.remove('$_localScanCountPrefix$id');
    await prefs.remove('$_localFirstScanPrefix$id');
  }
}
