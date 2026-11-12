import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../domain/models/reward_models.dart';
import '../../../../core/services/anti_fraud_service.dart';

export '../../domain/models/reward_models.dart';

/// Pivot Bearings India - Authoritative Reward Service
///
/// Handles atomic 1st-scan reward claims, user wallet balances,
/// redemption submissions, and admin approvals with notes/UTRs.
class RewardService {
  static const String _prefKeyOfflineWallet = 'pbi_offline_reward_wallet_';
  static const String _prefKeyOfflineClaimedBearings = 'pbi_reward_claimed_bearings';
  static const String _prefKeyOfflineRedemptions = 'pbi_offline_redemptions';
  static const String _prefKeyOfflineSettings = 'pbi_offline_reward_settings';

  /// Live reactive reward profile state for instant (0ms) UI updates across screens
  static final ValueNotifier<RewardProfile?> liveProfileNotifier = ValueNotifier<RewardProfile?>(null);
  static RewardSettings? _cachedSettings;
  static final Map<String, RewardClaimResult> _recentClaimsCache = {};

  static RewardClaimResult? getRecentClaimForBearing(String rawPayloadOrId) {
    final id = _extractBearingId(rawPayloadOrId);
    if (id.isEmpty) return null;
    final uid = AuthController.instance.userId ?? AuthController.instance.userEmail ?? 'anon';
    return _recentClaimsCache['$uid:${id.toUpperCase()}'];
  }

  static void _cacheClaimResult(String rawPayloadOrId, RewardClaimResult claim) {
    if (!claim.rewardAwarded && !claim.alreadyClaimed && !claim.isUserBlocked) return;
    final id = _extractBearingId(claim.bearingId ?? rawPayloadOrId);
    if (id.isEmpty) return;
    final uid = AuthController.instance.userId ?? AuthController.instance.userEmail ?? 'anon';
    _recentClaimsCache['$uid:${id.toUpperCase()}'] = claim;
  }

  static void _notifyLiveClaim(RewardClaimResult claim) {
    if (!claim.rewardAwarded) return;
    final prev = liveProfileNotifier.value ?? RewardProfile.defaultProfile();
    final newBalance = claim.newBalance > 0
        ? claim.newBalance
        : (prev.currentBalancePoints + claim.pointsEarned);
    final newEarned = prev.totalPointsEarned + claim.pointsEarned;
    liveProfileNotifier.value = RewardProfile(
      currentBalancePoints: newBalance,
      currentBalanceInr: prev.calculateInrForPoints(newBalance),
      pendingRedemptionPoints: prev.pendingRedemptionPoints,
      pendingRedemptionInr: prev.pendingRedemptionInr,
      totalPointsEarned: newEarned,
      totalPointsRedeemed: prev.totalPointsRedeemed,
      pointsBaseUnit: prev.pointsBaseUnit,
      inrPerBaseUnit: prev.inrPerBaseUnit,
      rateMultiplier: prev.rateMultiplier,
      rateDisplayString: prev.rateDisplayString,
      minRedemptionPoints: prev.minRedemptionPoints,
      minRedemptionInr: prev.minRedemptionInr,
      isEnabled: prev.isEnabled,
      isRewardEligible: prev.isRewardEligible,
      termsAndConditions: prev.termsAndConditions,
    );
  }

  static void _notifyLiveRedemption(int points) {
    final prev = liveProfileNotifier.value;
    if (prev == null || points <= 0) return;
    final newBalance = math.max(0, prev.currentBalancePoints - points);
    final newPending = prev.pendingRedemptionPoints + points;
    liveProfileNotifier.value = RewardProfile(
      currentBalancePoints: newBalance,
      currentBalanceInr: prev.calculateInrForPoints(newBalance),
      pendingRedemptionPoints: newPending,
      pendingRedemptionInr: prev.calculateInrForPoints(newPending),
      totalPointsEarned: prev.totalPointsEarned,
      totalPointsRedeemed: prev.totalPointsRedeemed,
      pointsBaseUnit: prev.pointsBaseUnit,
      inrPerBaseUnit: prev.inrPerBaseUnit,
      rateMultiplier: prev.rateMultiplier,
      rateDisplayString: prev.rateDisplayString,
      minRedemptionPoints: prev.minRedemptionPoints,
      minRedemptionInr: prev.minRedemptionInr,
      isEnabled: prev.isEnabled,
      isRewardEligible: prev.isRewardEligible,
      termsAndConditions: prev.termsAndConditions,
    );
  }

  // ===========================================================================
  // 1. ATOMIC 1ST-SCAN REWARD CLAIM (With Mandatory Supplier Details)
  // ===========================================================================
  /// Invoked whenever a user claims/receives reward points for an authentic bearing QR code.
  /// Rewarding points does NOT require supplier info.
  static Future<RewardClaimResult> claimBearingScanReward({
    required String rawPayloadOrId,
    required String sourceModule,
    String? supplierName,
    String? supplierContact,
  }) async {
    final clean = rawPayloadOrId.trim();
    final cleanSuppName = supplierName?.trim();
    final cleanSuppContact = supplierContact?.trim();

    if (clean.isEmpty) {
      return RewardClaimResult.empty(message: 'Invalid code.');
    }

    if (SupabaseService.isInitialized) {
      try {
        final dynamic res = await SupabaseService.client.rpc(
          'claim_bearing_scan_reward',
          params: {
            'p_bearing_id': clean,
            'p_source_module': sourceModule,
            'p_supplier_name': cleanSuppName,
            'p_supplier_contact': cleanSuppContact,
          },
        );

        if (res != null && res is Map) {
          final data = Map<String, dynamic>.from(res);
          final errorCode = data['error_code']?.toString();
          if (errorCode != 'UNAUTHORIZED') {
            final claim = RewardClaimResult.fromJson(data);
            _cacheClaimResult(clean, claim);
            _notifyLiveClaim(claim);
            return claim;
          }
          debugPrint('claim_bearing_scan_reward returned UNAUTHORIZED, falling back to local engine');
        }
      } catch (e) {
        debugPrint('Supabase claim_bearing_scan_reward error, falling back to local engine: $e');
      }
    }

    // Offline / Local Resilience Fallback
    final localClaim = await _localClaimBearingReward(
      clean,
      sourceModule,
      supplierName: cleanSuppName,
      supplierContact: cleanSuppContact,
    );
    _cacheClaimResult(clean, localClaim);
    _notifyLiveClaim(localClaim);
    return localClaim;
  }

  /// Checks if reward has already been claimed for a given bearing ID
  static Future<bool> isBearingRewardClaimed(String rawPayloadOrId) async {
    final clean = rawPayloadOrId.trim();
    if (clean.isEmpty) return false;
    final bearingId = _extractBearingId(clean);
    if (SupabaseService.isInitialized) {
      try {
        // 1. Exact match
        var res = await SupabaseService.client
            .from('qr_codes')
            .select('is_reward_claimed')
            .eq('bearing_id', bearingId)
            .maybeSingle();
        if (res != null) {
          return res['is_reward_claimed'] == true;
        }
        // 2. Case-insensitive match
        res = await SupabaseService.client
            .from('qr_codes')
            .select('is_reward_claimed')
            .ilike('bearing_id', bearingId)
            .maybeSingle();
        if (res != null) {
          return res['is_reward_claimed'] == true;
        }
        // 3. Payload match
        if (clean != bearingId) {
          res = await SupabaseService.client
              .from('qr_codes')
              .select('is_reward_claimed')
              .eq('payload_value', clean)
              .maybeSingle();
          if (res != null) {
            return res['is_reward_claimed'] == true;
          }
        }
      } catch (e) {
        debugPrint('isBearingRewardClaimed query error: $e');
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final claimedList = prefs.getStringList(_prefKeyOfflineClaimedBearings) ?? [];
    return claimedList.contains(bearingId) ||
        claimedList.contains(clean) ||
        claimedList.contains(bearingId.toUpperCase());
  }

  // ===========================================================================
  // 2. USER REWARD PROFILE & WALLET BALANCE
  // ===========================================================================
  static Future<RewardProfile> fetchUserRewardProfile() async {
    RewardProfile? onlineProfile;
    if (SupabaseService.isInitialized) {
      try {
        final dynamic res = await SupabaseService.client.rpc('get_user_reward_profile');
        if (res != null && res is Map) {
          final data = Map<String, dynamic>.from(res);
          if (data['authenticated'] == true) {
            onlineProfile = RewardProfile.fromJson(data);
          }
        }
      } catch (e) {
        debugPrint('Supabase get_user_reward_profile error: $e');
      }
    }

    if (onlineProfile != null) {
      // Read local fallback balance from SharedPreferences only (no redundant network settings call)
      final localProfile = await _localGetUserRewardProfile(skipRemoteSettings: true);
      final maxBalance = math.max(onlineProfile.currentBalancePoints, localProfile.currentBalancePoints);
      final maxEarned = math.max(onlineProfile.totalPointsEarned, localProfile.totalPointsEarned);
      final resolved = maxBalance > onlineProfile.currentBalancePoints
          ? RewardProfile(
              currentBalancePoints: maxBalance,
              currentBalanceInr: onlineProfile.calculateInrForPoints(maxBalance),
              pendingRedemptionPoints: onlineProfile.pendingRedemptionPoints,
              pendingRedemptionInr: onlineProfile.pendingRedemptionInr,
              totalPointsEarned: maxEarned,
              totalPointsRedeemed: onlineProfile.totalPointsRedeemed,
              pointsBaseUnit: onlineProfile.pointsBaseUnit,
              inrPerBaseUnit: onlineProfile.inrPerBaseUnit,
              rateMultiplier: onlineProfile.rateMultiplier,
              rateDisplayString: onlineProfile.rateDisplayString,
              minRedemptionPoints: onlineProfile.minRedemptionPoints,
              minRedemptionInr: onlineProfile.minRedemptionInr,
              isEnabled: onlineProfile.isEnabled,
              isRewardEligible: onlineProfile.isRewardEligible,
              termsAndConditions: onlineProfile.termsAndConditions,
            )
          : onlineProfile;
      liveProfileNotifier.value = resolved;
      return resolved;
    }

    final localProfile = await _localGetUserRewardProfile();
    liveProfileNotifier.value = localProfile;
    return localProfile;
  }

  // ===========================================================================
  // 3. USER REDEMPTION SUBMISSION
  // ===========================================================================
  static Future<Map<String, dynamic>> submitRedemptionRequest({
    required int points,
    required String payoutMethod,
    required String supplierName,
    required String supplierContact,
    String? upiId,
    String? bankAccountNumber,
    String? bankIfsc,
    String? bankAccountHolderName,
    String? bankName,
  }) async {
    final cleanSuppName = supplierName.trim();
    final cleanSuppContact = supplierContact.trim();

    if (cleanSuppName.isEmpty || cleanSuppContact.isEmpty) {
      return {
        'success': false,
        'message': 'Supplier Name and Contact Number are mandatory to redeem points.',
      };
    }

    if (SupabaseService.isInitialized) {
      try {
        final dynamic res = await SupabaseService.client.rpc(
          'request_reward_redemption',
          params: {
            'p_points': points,
            'p_payout_method': payoutMethod,
            'p_upi_id': upiId,
            'p_bank_account': bankAccountNumber,
            'p_bank_ifsc': bankIfsc,
            'p_bank_holder_name': bankAccountHolderName,
            'p_bank_name': bankName,
            'p_supplier_name': cleanSuppName,
            'p_supplier_contact': cleanSuppContact,
          },
        );

        if (res != null && res is Map) {
          final map = Map<String, dynamic>.from(res);
          if (map['success'] == true) {
            _notifyLiveRedemption(points);
            return map;
          }
          // If RPC returned an explicit functional rejection (e.g. min points not met), return it
          if (map['message'] != null && map['message'].toString().contains('threshold')) {
            return map;
          }
        }
      } catch (e) {
        debugPrint('Supabase request_reward_redemption error, falling back to resilient local engine: $e');
      }
    }

    final localRes = await _localSubmitRedemption(
      points: points,
      payoutMethod: payoutMethod,
      supplierName: cleanSuppName,
      supplierContact: cleanSuppContact,
      upiId: upiId,
      bankAccountNumber: bankAccountNumber,
      bankIfsc: bankIfsc,
      bankAccountHolderName: bankAccountHolderName,
      bankName: bankName,
    );
    if (localRes['success'] == true) {
      _notifyLiveRedemption(points);
    }
    return localRes;
  }

  // ===========================================================================
  // 4. USER TRANSACTIONS & REDEMPTION LISTS (PAGINATED AT 10 PER PAGE)
  // ===========================================================================
  static Future<PaginatedRewardResult<RewardTransaction>> fetchUserTransactionsPaginated({
    int page = 0,
    int pageSize = 10,
  }) async {
    List<RewardTransaction> onlineItems = [];
    int onlineCount = 0;
    if (SupabaseService.isInitialized) {
      try {
        final uid = AuthController.instance.userId ?? SupabaseService.currentUserId;
        if (uid != null) {
          final from = page * pageSize;
          final to = from + pageSize - 1;
          final results = await Future.wait<dynamic>([
            SupabaseService.client
                .from('reward_transactions')
                .count(CountOption.exact)
                .eq('user_id', uid),
            SupabaseService.client
                .from('reward_transactions')
                .select()
                .eq('user_id', uid)
                .order('created_at', ascending: false)
                .range(from, to),
          ]);

          onlineCount = results[0] as int;
          onlineItems = (results[1] as List)
              .map((row) => RewardTransaction.fromJson(Map<String, dynamic>.from(row)))
              .toList();
        }
      } catch (e) {
        debugPrint('Supabase fetchUserTransactionsPaginated error: $e');
      }
    }

    if (onlineItems.isNotEmpty) {
      return PaginatedRewardResult<RewardTransaction>(
        items: onlineItems,
        totalCount: onlineCount,
        page: page,
        pageSize: pageSize,
      );
    }

    final localAll = await _localGetUserTransactions();
    final from = page * pageSize;
    final items = localAll.skip(from).take(pageSize).toList();
    return PaginatedRewardResult<RewardTransaction>(
      items: items,
      totalCount: localAll.length,
      page: page,
      pageSize: pageSize,
    );
  }

  static Future<List<RewardTransaction>> fetchUserTransactions({int limit = 10, int offset = 0}) async {
    final paginated = await fetchUserTransactionsPaginated(page: offset ~/ limit, pageSize: limit);
    return paginated.items;
  }

  static Future<PaginatedRewardResult<RewardRedemption>> fetchUserRedemptionsPaginated({
    int page = 0,
    int pageSize = 10,
  }) async {
    List<RewardRedemption> onlineItems = [];
    int onlineCount = 0;
    if (SupabaseService.isInitialized) {
      try {
        final uid = AuthController.instance.userId ?? SupabaseService.currentUserId;
        if (uid != null) {
          final from = page * pageSize;
          final to = from + pageSize - 1;
          final results = await Future.wait<dynamic>([
            SupabaseService.client
                .from('reward_redemptions')
                .count(CountOption.exact)
                .eq('user_id', uid),
            SupabaseService.client
                .from('reward_redemptions')
                .select()
                .eq('user_id', uid)
                .order('created_at', ascending: false)
                .range(from, to),
          ]);

          onlineCount = results[0] as int;
          onlineItems = (results[1] as List)
              .map((row) => RewardRedemption.fromJson(Map<String, dynamic>.from(row)))
              .toList();
        }
      } catch (e) {
        debugPrint('Supabase fetchUserRedemptionsPaginated error: $e');
      }
    }

    if (onlineItems.isNotEmpty) {
      return PaginatedRewardResult<RewardRedemption>(
        items: onlineItems,
        totalCount: onlineCount,
        page: page,
        pageSize: pageSize,
      );
    }

    final localAll = await _localGetUserRedemptions();
    final from = page * pageSize;
    final items = localAll.skip(from).take(pageSize).toList();
    return PaginatedRewardResult<RewardRedemption>(
      items: items,
      totalCount: localAll.length,
      page: page,
      pageSize: pageSize,
    );
  }

  static Future<List<RewardRedemption>> fetchUserRedemptions({int limit = 10, int offset = 0}) async {
    final paginated = await fetchUserRedemptionsPaginated(page: offset ~/ limit, pageSize: limit);
    return paginated.items;
  }

  // ===========================================================================
  // 5. ADMIN MANAGEMENT & SETTINGS
  // ===========================================================================
  static Future<RewardSettings> fetchRewardSettings() async {
    if (SupabaseService.isInitialized) {
      try {
        final res = await SupabaseService.client
            .from('reward_settings')
            .select()
            .eq('id', 1)
            .maybeSingle();

        if (res != null) {
          final settings = RewardSettings.fromJson(Map<String, dynamic>.from(res));
          _cachedSettings = settings;
          return settings;
        }
      } catch (e) {
        debugPrint('Supabase fetchRewardSettings error: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKeyOfflineSettings);
    if (raw != null) {
      try {
        final settings = RewardSettings.fromJson(jsonDecode(raw));
        _cachedSettings = settings;
        return settings;
      } catch (_) {}
    }
    return _cachedSettings ?? const RewardSettings();
  }

  static Future<bool> updateRewardSettings({
    required int pointsBaseUnit,
    required double inrPerBaseUnit,
    required int pointsPerFirstScan,
    required int minRedemptionPoints,
    required bool isEnabled,
    required int dailyMaxScans,
    String? termsAndConditions,
  }) async {
    // Update anti-fraud threshold
    await AntiFraudService.setFraudLimit(dailyMaxScans);

    if (SupabaseService.isInitialized) {
      try {
        final dynamic res = await SupabaseService.client.rpc(
          'admin_update_reward_settings',
          params: {
            'p_points_base_unit': pointsBaseUnit,
            'p_inr_per_base_unit': inrPerBaseUnit,
            'p_points_per_first_scan': pointsPerFirstScan,
            'p_min_redemption_points': minRedemptionPoints,
            'p_is_enabled': isEnabled,
            'p_daily_max_scans': dailyMaxScans,
            'p_terms_and_conditions': termsAndConditions,
          },
        );

        if (res != null && res is Map && res['success'] == true) {
          final prefs = await SharedPreferences.getInstance();
          final settings = RewardSettings(
            pointsBaseUnit: pointsBaseUnit,
            inrPerBaseUnit: inrPerBaseUnit,
            pointsPerFirstScan: pointsPerFirstScan,
            minRedemptionPoints: minRedemptionPoints,
            isEnabled: isEnabled,
            dailyMaxScans: dailyMaxScans,
            termsAndConditions: termsAndConditions ??
                'Pivot Bearings reserves the right to modify, adjust, or change the reward point conversion value (Points to INR rate) and program rules at any time without prior notice.',
          );
          await prefs.setString(_prefKeyOfflineSettings, jsonEncode(settings.toJson()));
          return true;
        }
      } catch (e) {
        debugPrint('Supabase updateRewardSettings error: $e');
      }
    }

    // Cache locally
    try {
      final prefs = await SharedPreferences.getInstance();
      final settings = RewardSettings(
        pointsBaseUnit: pointsBaseUnit,
        inrPerBaseUnit: inrPerBaseUnit,
        pointsPerFirstScan: pointsPerFirstScan,
        minRedemptionPoints: minRedemptionPoints,
        isEnabled: isEnabled,
        dailyMaxScans: dailyMaxScans,
        termsAndConditions: termsAndConditions ??
            'Pivot Bearings reserves the right to modify, adjust, or change the reward point conversion value (Points to INR rate) and program rules at any time without prior notice.',
      );
      await prefs.setString(_prefKeyOfflineSettings, jsonEncode(settings.toJson()));
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<PaginatedRewardResult<RewardRedemption>> fetchAdminRedemptionsPaginated({
    String? statusFilter,
    int page = 0,
    int pageSize = 10,
  }) async {
    if (SupabaseService.isInitialized) {
      try {
        var countQuery = SupabaseService.client.from('reward_redemptions').count(CountOption.exact);
        if (statusFilter != null && statusFilter != 'ALL') {
          countQuery = countQuery.eq('status', statusFilter);
        }
        final totalCount = await countQuery;

        var query = SupabaseService.client.from('reward_redemptions').select('*');
        if (statusFilter != null && statusFilter != 'ALL') {
          query = query.eq('status', statusFilter);
        }

        final from = page * pageSize;
        final to = from + pageSize - 1;
        final res = await query.order('created_at', ascending: false).range(from, to);
        final rows = List<Map<String, dynamic>>.from(
          (res as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );

        if (rows.isNotEmpty) {
          final userIds = rows
              .map((r) => r['user_id']?.toString())
              .whereType<String>()
              .toSet()
              .toList();

          if (userIds.isNotEmpty) {
            try {
              final profRes = await SupabaseService.client
                  .from('profiles')
                  .select('id, email, full_name, phone')
                  .inFilter('id', userIds);

              final profileMap = {
                for (final p in (profRes as List))
                  (p as Map)['id']?.toString(): Map<String, dynamic>.from(p)
              };

              for (final r in rows) {
                final uid = r['user_id']?.toString();
                if (uid != null && profileMap.containsKey(uid)) {
                  final p = profileMap[uid]!;
                  r['user_email'] = p['email'];
                  r['user_name'] = p['full_name'];
                  r['user_phone'] = p['phone'];
                }
              }
            } catch (_) {}
          }
        }

        final items = rows.map((row) => RewardRedemption.fromJson(row)).toList();
        return PaginatedRewardResult<RewardRedemption>(
          items: items,
          totalCount: totalCount,
          page: page,
          pageSize: pageSize,
        );
      } catch (e) {
        debugPrint('Supabase fetchAdminRedemptionsPaginated error: $e');
      }
    }

    final all = await _localGetAllRedemptions(statusFilter);
    final from = page * pageSize;
    final items = all.skip(from).take(pageSize).toList();
    return PaginatedRewardResult<RewardRedemption>(
      items: items,
      totalCount: all.length,
      page: page,
      pageSize: pageSize,
    );
  }

  static Future<List<RewardRedemption>> fetchAdminRedemptions({String? statusFilter, int limit = 10, int offset = 0}) async {
    final paginated = await fetchAdminRedemptionsPaginated(
      statusFilter: statusFilter,
      page: offset ~/ limit,
      pageSize: limit,
    );
    return paginated.items;
  }

  static Future<Map<String, dynamic>> adminProcessRedemption({
    required String redemptionId,
    required String action, // 'APPROVE' or 'REJECT'
    String? paymentRef,
    String? paymentMode,
    String? notes,
  }) async {
    if (SupabaseService.isInitialized) {
      try {
        final dynamic res = await SupabaseService.client.rpc(
          'admin_process_redemption',
          params: {
            'p_redemption_id': redemptionId,
            'p_action': action,
            'p_payment_ref': paymentRef,
            'p_payment_mode': paymentMode,
            'p_notes': notes,
          },
        );

        if (res != null && res is Map) {
          return Map<String, dynamic>.from(res);
        }
      } catch (e) {
        debugPrint('Supabase admin_process_redemption error: $e');
        return {
          'success': false,
          'message': 'Failed: ${e.toString()}',
        };
      }
    }

    return await _localAdminProcessRedemption(
      redemptionId: redemptionId,
      action: action,
      paymentRef: paymentRef,
      paymentMode: paymentMode,
      notes: notes,
    );
  }

  // ===========================================================================
  // 6. LOCAL RESILIENCE / OFFLINE FALLBACK IMPLEMENTATION
  // ===========================================================================
  static Future<RewardClaimResult> _localClaimBearingReward(
    String rawPayload,
    String sourceModule, {
    String? supplierName,
    String? supplierContact,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final claimedList = prefs.getStringList(_prefKeyOfflineClaimedBearings) ?? [];
    final bearingId = _extractBearingId(rawPayload);
    final userEmail = AuthController.instance.userEmail ?? 'default_user';
    final cleanEmail = userEmail.trim().toLowerCase();

    final cleanName = supplierName?.trim() ?? '';
    final cleanContact = supplierContact?.trim() ?? '';

    // Check if user is blocked from receiving rewards
    final isBlocked = !AuthController.instance.isRewardEligible ||
        prefs.getBool('offline_reward_eligible_$cleanEmail') == false ||
        prefs.getBool('offline_reward_eligible_$userEmail') == false;
    if (isBlocked) {
      return RewardClaimResult(
        rewardAwarded: false,
        isUserBlocked: true,
        bearingId: bearingId,
        message: 'Bearing verified authentic. Promotional reward points are currently inactive for this account profile.',
      );
    }

    if (claimedList.any((c) => c.toUpperCase() == bearingId.toUpperCase())) {
      return RewardClaimResult(
        rewardAwarded: false,
        alreadyClaimed: true,
        bearingId: bearingId,
        message: 'First-scan reward has already been claimed for this bearing.',
      );
    }

    // Award reward
    final settings = await fetchRewardSettings();
    if (!settings.isEnabled) {
      return RewardClaimResult.empty(message: 'Reward program is currently paused.');
    }

    final points = settings.pointsPerFirstScan;
    final inr = (points * (settings.inrPerBaseUnit / settings.pointsBaseUnit));

    claimedList.add(bearingId);
    await prefs.setStringList(_prefKeyOfflineClaimedBearings, claimedList);
    await prefs.setString('pbi_supplier_name_$bearingId', cleanName);
    await prefs.setString('pbi_supplier_contact_$bearingId', cleanContact);

    final curBal = prefs.getInt('${_prefKeyOfflineWallet}balance_$userEmail') ?? 0;
    final totalEarned = prefs.getInt('${_prefKeyOfflineWallet}earned_$userEmail') ?? 0;

    final newBal = curBal + points;
    await prefs.setInt('${_prefKeyOfflineWallet}balance_$userEmail', newBal);
    await prefs.setInt('${_prefKeyOfflineWallet}earned_$userEmail', totalEarned + points);

    // Record local transaction ledger entry so user wallet reflects earned points
    try {
      final txn = {
        'id': 'local_tx_${DateTime.now().millisecondsSinceEpoch}',
        'bearing_id': bearingId,
        'transaction_type': 'SCAN_CREDIT',
        'points': points,
        'amount_inr': inr,
        'source_module': sourceModule,
        'description': '1st Scan reward for bearing $bearingId',
        'created_at': DateTime.now().toIso8601String(),
      };
      final rawTx = prefs.getString('${_prefKeyOfflineWallet}txns_$userEmail');
      List<dynamic> txList = rawTx != null ? jsonDecode(rawTx) : [];
      txList.insert(0, txn);
      await prefs.setString('${_prefKeyOfflineWallet}txns_$userEmail', jsonEncode(txList));
    } catch (_) {}

    return RewardClaimResult(
      rewardAwarded: true,
      bearingId: bearingId,
      pointsEarned: points,
      amountInr: inr,
      rateDisplay: '${settings.pointsBaseUnit} Points = ₹${settings.inrPerBaseUnit.toStringAsFixed(2)}',
      newBalance: newBal,
      supplierName: cleanName,
      supplierContact: cleanContact,
      message: 'Congratulations! $points Reward Points added to your Pivot Wallet.',
    );
  }

  static Future<RewardProfile> _localGetUserRewardProfile({bool skipRemoteSettings = false}) async {
    final prefs = await SharedPreferences.getInstance();
    RewardSettings settings;
    if (skipRemoteSettings) {
      final raw = prefs.getString(_prefKeyOfflineSettings);
      if (_cachedSettings != null) {
        settings = _cachedSettings!;
      } else if (raw != null) {
        try {
          settings = RewardSettings.fromJson(jsonDecode(raw));
        } catch (_) {
          settings = const RewardSettings();
        }
      } else {
        settings = const RewardSettings();
      }
    } else {
      settings = await fetchRewardSettings();
    }
    final userEmail = AuthController.instance.userEmail ?? 'default_user';
    final isEligible = prefs.getBool('offline_reward_eligible_$userEmail') != false;

    final balance = prefs.getInt('${_prefKeyOfflineWallet}balance_$userEmail') ?? 0;
    final pending = prefs.getInt('${_prefKeyOfflineWallet}pending_$userEmail') ?? 0;
    final totalEarned = prefs.getInt('${_prefKeyOfflineWallet}earned_$userEmail') ?? 0;
    final totalRedeemed = prefs.getInt('${_prefKeyOfflineWallet}redeemed_$userEmail') ?? 0;

    final mult = settings.inrPerBaseUnit / settings.pointsBaseUnit;

    return RewardProfile(
      currentBalancePoints: balance,
      currentBalanceInr: balance * mult,
      pendingRedemptionPoints: pending,
      pendingRedemptionInr: pending * mult,
      totalPointsEarned: totalEarned,
      totalPointsRedeemed: totalRedeemed,
      pointsBaseUnit: settings.pointsBaseUnit,
      inrPerBaseUnit: settings.inrPerBaseUnit,
      rateMultiplier: mult,
      rateDisplayString: '${settings.pointsBaseUnit} Points = ₹${settings.inrPerBaseUnit.toStringAsFixed(2)}',
      minRedemptionPoints: settings.minRedemptionPoints,
      minRedemptionInr: settings.minRedemptionPoints * mult,
      isEnabled: settings.isEnabled,
      isRewardEligible: isEligible,
      termsAndConditions: settings.termsAndConditions,
    );
  }

  static Future<Map<String, dynamic>> _localSubmitRedemption({
    required int points,
    required String payoutMethod,
    required String supplierName,
    required String supplierContact,
    String? upiId,
    String? bankAccountNumber,
    String? bankIfsc,
    String? bankAccountHolderName,
    String? bankName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = await fetchRewardSettings();
    final userEmail = AuthController.instance.userEmail ?? 'default_user';

    final curBal = prefs.getInt('${_prefKeyOfflineWallet}balance_$userEmail') ?? 0;
    if (curBal < points) {
      return {'success': false, 'message': 'Insufficient point balance.'};
    }
    if (points < settings.minRedemptionPoints) {
      return {'success': false, 'message': 'Minimum redemption is ${settings.minRedemptionPoints} points.'};
    }

    final curPending = prefs.getInt('${_prefKeyOfflineWallet}pending_$userEmail') ?? 0;
    await prefs.setInt('${_prefKeyOfflineWallet}balance_$userEmail', curBal - points);
    await prefs.setInt('${_prefKeyOfflineWallet}pending_$userEmail', curPending + points);

    final reqNum = 'RED-${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final mult = settings.inrPerBaseUnit / settings.pointsBaseUnit;

    final newReq = {
      'id': 'local_${DateTime.now().millisecondsSinceEpoch}',
      'request_number': reqNum,
      'user_id': userEmail,
      'points_requested': points,
      'amount_in_inr': points * mult,
      'payout_method': payoutMethod,
      'upi_id': upiId,
      'bank_account_number': bankAccountNumber,
      'bank_ifsc': bankIfsc,
      'bank_account_holder_name': bankAccountHolderName,
      'bank_name': bankName,
      'supplier_name': supplierName,
      'supplier_contact': supplierContact,
      'status': 'PENDING',
      'created_at': DateTime.now().toIso8601String(),
      'user_email': userEmail,
      'user_name': AuthController.instance.userName ?? userEmail.split('@').first,
    };

    final raw = prefs.getString(_prefKeyOfflineRedemptions);
    List<dynamic> list = raw != null ? jsonDecode(raw) : [];
    list.insert(0, newReq);
    await prefs.setString(_prefKeyOfflineRedemptions, jsonEncode(list));

    // Record redemption hold in local transactions ledger
    try {
      final txn = {
        'id': 'local_tx_${DateTime.now().millisecondsSinceEpoch}',
        'transaction_type': 'REDEMPTION_HOLD',
        'points': -points,
        'amount_inr': -(points * mult),
        'source_module': 'REDEMPTION',
        'description': 'Payout request $reqNum ($payoutMethod)',
        'created_at': DateTime.now().toIso8601String(),
      };
      final rawTx = prefs.getString('${_prefKeyOfflineWallet}txns_$userEmail');
      List<dynamic> txList = rawTx != null ? jsonDecode(rawTx) : [];
      txList.insert(0, txn);
      await prefs.setString('${_prefKeyOfflineWallet}txns_$userEmail', jsonEncode(txList));
    } catch (_) {}

    return {
      'success': true,
      'request_number': reqNum,
      'points_requested': points,
      'amount_in_inr': points * mult,
      'status': 'PENDING',
      'message': 'Redemption request submitted successfully!',
    };
  }

  static Future<List<RewardTransaction>> _localGetUserTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final userEmail = AuthController.instance.userEmail ?? 'default_user';
    final raw = prefs.getString('${_prefKeyOfflineWallet}txns_$userEmail');
    if (raw == null) return [];
    try {
      final list = List<Map<String, dynamic>>.from(jsonDecode(raw));
      return list.map((item) => RewardTransaction.fromJson(item)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<RewardRedemption>> _localGetUserRedemptions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKeyOfflineRedemptions);
    if (raw == null) return [];
    try {
      final list = List<Map<String, dynamic>>.from(jsonDecode(raw));
      final userEmail = AuthController.instance.userEmail ?? 'default_user';
      return list
          .where((item) => item['user_id'] == userEmail)
          .map((item) => RewardRedemption.fromJson(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<RewardRedemption>> _localGetAllRedemptions(String? statusFilter) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKeyOfflineRedemptions);
    if (raw == null) return [];
    try {
      final list = List<Map<String, dynamic>>.from(jsonDecode(raw));
      var filtered = list;
      if (statusFilter != null && statusFilter != 'ALL') {
        filtered = list.where((item) => item['status'] == statusFilter).toList();
      }
      return filtered.map((item) => RewardRedemption.fromJson(item)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> _localAdminProcessRedemption({
    required String redemptionId,
    required String action,
    String? paymentRef,
    String? paymentMode,
    String? notes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKeyOfflineRedemptions);
    if (raw == null) return {'success': false, 'message': 'Request not found.'};

    try {
      final list = List<Map<String, dynamic>>.from(jsonDecode(raw));
      final idx = list.indexWhere((item) => item['id'] == redemptionId);
      if (idx == -1) return {'success': false, 'message': 'Request not found.'};

      final req = list[idx];
      final userEmail = req['user_id']?.toString() ?? 'default_user';
      final pts = (req['points_requested'] as num?)?.toInt() ?? 0;
      final curPending = prefs.getInt('${_prefKeyOfflineWallet}pending_$userEmail') ?? 0;

      if (action.toUpperCase() == 'APPROVE') {
        req['status'] = 'COMPLETED';
        req['payment_reference_id'] = paymentRef;
        req['payment_mode'] = paymentMode;
        req['admin_notes'] = notes;
        req['actioned_at'] = DateTime.now().toIso8601String();

        await prefs.setInt('${_prefKeyOfflineWallet}pending_$userEmail', (curPending - pts).clamp(0, 99999999));
        final curRedeemed = prefs.getInt('${_prefKeyOfflineWallet}redeemed_$userEmail') ?? 0;
        await prefs.setInt('${_prefKeyOfflineWallet}redeemed_$userEmail', curRedeemed + pts);
      } else {
        req['status'] = 'REJECTED';
        req['admin_notes'] = notes ?? 'Rejected by Administrator';
        req['actioned_at'] = DateTime.now().toIso8601String();

        await prefs.setInt('${_prefKeyOfflineWallet}pending_$userEmail', (curPending - pts).clamp(0, 99999999));
        final curBal = prefs.getInt('${_prefKeyOfflineWallet}balance_$userEmail') ?? 0;
        await prefs.setInt('${_prefKeyOfflineWallet}balance_$userEmail', curBal + pts);
      }

      list[idx] = req;
      await prefs.setString(_prefKeyOfflineRedemptions, jsonEncode(list));

      return {
        'success': true,
        'status': req['status'],
        'message': 'Processed successfully.',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static String _extractBearingId(String payload) {
    var id = payload.trim();
    if (id.contains('/pbi/')) {
      final parts = id.split('/pbi/');
      if (parts.length > 1) {
        id = parts[1].split('?').first.split('&').first;
      }
    } else if (id.contains('/verify/')) {
      final parts = id.split('/verify/');
      if (parts.length > 1) {
        id = parts[1].split('?').first.split('&').first;
      }
    } else if (id.contains('://')) {
      final uri = Uri.tryParse(id);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        id = uri.pathSegments.last.split('?').first;
      }
    }
    try {
      id = Uri.decodeComponent(id);
    } catch (_) {}
    return id.trim();
  }
}
