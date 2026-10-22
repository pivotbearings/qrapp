import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../domain/models/reward_models.dart';

/// Pivot Bearings India - Authoritative Reward Service
///
/// Handles atomic 1st-scan reward claims, user wallet balances,
/// redemption submissions, and admin approvals with notes/UTRs.
class RewardService {
  static const String _prefKeyOfflineWallet = 'pbi_offline_reward_wallet_';
  static const String _prefKeyOfflineClaimedBearings = 'pbi_reward_claimed_bearings';
  static const String _prefKeyOfflineRedemptions = 'pbi_offline_redemptions';
  static const String _prefKeyOfflineSettings = 'pbi_offline_reward_settings';

  // ===========================================================================
  // 1. ATOMIC 1ST-SCAN REWARD CLAIM (Across All Modules)
  // ===========================================================================
  /// Invoked whenever a bearing QR code is scanned in:
  /// - Authenticate Bearing
  /// - Track Bearing In/Out
  /// - Warranty Check & In/Out flow
  static Future<RewardClaimResult> claimBearingScanReward({
    required String rawPayloadOrId,
    required String sourceModule,
  }) async {
    final clean = rawPayloadOrId.trim();
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
          },
        );

        if (res != null && res is Map) {
          final data = Map<String, dynamic>.from(res);
          return RewardClaimResult.fromJson(data);
        }
      } catch (e) {
        debugPrint('Supabase claim_bearing_scan_reward error, falling back to local engine: $e');
      }
    }

    // Offline / Local Resilience Fallback
    return await _localClaimBearingReward(clean, sourceModule);
  }

  // ===========================================================================
  // 2. USER REWARD PROFILE & WALLET BALANCE
  // ===========================================================================
  static Future<RewardProfile> fetchUserRewardProfile() async {
    if (SupabaseService.isInitialized) {
      try {
        final dynamic res = await SupabaseService.client.rpc('get_user_reward_profile');
        if (res != null && res is Map) {
          final data = Map<String, dynamic>.from(res);
          if (data['authenticated'] == true) {
            return RewardProfile.fromJson(data);
          }
        }
      } catch (e) {
        debugPrint('Supabase get_user_reward_profile error: $e');
      }
    }

    return await _localGetUserRewardProfile();
  }

  // ===========================================================================
  // 3. USER REDEMPTION SUBMISSION
  // ===========================================================================
  static Future<Map<String, dynamic>> submitRedemptionRequest({
    required int points,
    required String payoutMethod,
    String? upiId,
    String? bankAccountNumber,
    String? bankIfsc,
    String? bankAccountHolderName,
    String? bankName,
  }) async {
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
          },
        );

        if (res != null && res is Map) {
          return Map<String, dynamic>.from(res);
        }
      } catch (e) {
        debugPrint('Supabase request_reward_redemption error: $e');
        return {
          'success': false,
          'message': 'Failed to submit request: ${e.toString()}',
        };
      }
    }

    return await _localSubmitRedemption(
      points: points,
      payoutMethod: payoutMethod,
      upiId: upiId,
      bankAccountNumber: bankAccountNumber,
      bankIfsc: bankIfsc,
      bankAccountHolderName: bankAccountHolderName,
      bankName: bankName,
    );
  }

  // ===========================================================================
  // 4. USER TRANSACTIONS & REDEMPTION LISTS
  // ===========================================================================
  static Future<List<RewardTransaction>> fetchUserTransactions() async {
    if (SupabaseService.isInitialized) {
      try {
        final uid = AuthController.instance.userId ?? SupabaseService.currentUserId;
        if (uid != null) {
          final res = await SupabaseService.client
              .from('reward_transactions')
              .select()
              .eq('user_id', uid)
              .order('created_at', ascending: false)
              .limit(100);

          return (res as List)
              .map((row) => RewardTransaction.fromJson(Map<String, dynamic>.from(row)))
              .toList();
        }
      } catch (e) {
        debugPrint('Supabase fetchUserTransactions error: $e');
      }
    }
    return [];
  }

  static Future<List<RewardRedemption>> fetchUserRedemptions() async {
    if (SupabaseService.isInitialized) {
      try {
        final uid = AuthController.instance.userId ?? SupabaseService.currentUserId;
        if (uid != null) {
          final res = await SupabaseService.client
              .from('reward_redemptions')
              .select()
              .eq('user_id', uid)
              .order('created_at', ascending: false)
              .limit(100);

          return (res as List)
              .map((row) => RewardRedemption.fromJson(Map<String, dynamic>.from(row)))
              .toList();
        }
      } catch (e) {
        debugPrint('Supabase fetchUserRedemptions error: $e');
      }
    }

    return await _localGetUserRedemptions();
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
          return RewardSettings.fromJson(Map<String, dynamic>.from(res));
        }
      } catch (e) {
        debugPrint('Supabase fetchRewardSettings error: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKeyOfflineSettings);
    if (raw != null) {
      try {
        return RewardSettings.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
    return const RewardSettings();
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

  static Future<List<RewardRedemption>> fetchAdminRedemptions({String? statusFilter}) async {
    if (SupabaseService.isInitialized) {
      try {
        var query = SupabaseService.client.from('reward_redemptions').select('*');
        if (statusFilter != null && statusFilter != 'ALL') {
          query = query.eq('status', statusFilter);
        }

        final res = await query.order('created_at', ascending: false).limit(200);
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

        return rows.map((row) => RewardRedemption.fromJson(row)).toList();
      } catch (e) {
        debugPrint('Supabase fetchAdminRedemptions error: $e');
      }
    }

    return await _localGetAllRedemptions(statusFilter);
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
  static Future<RewardClaimResult> _localClaimBearingReward(String rawPayload, String sourceModule) async {
    final prefs = await SharedPreferences.getInstance();
    final claimedList = prefs.getStringList(_prefKeyOfflineClaimedBearings) ?? [];
    final bearingId = _extractBearingId(rawPayload);
    final userEmail = AuthController.instance.userEmail ?? 'default_user';

    // Check if user is blocked from receiving rewards
    final isBlocked = prefs.getBool('offline_reward_eligible_$userEmail') == false;
    if (isBlocked) {
      return RewardClaimResult(
        rewardAwarded: false,
        isUserBlocked: true,
        bearingId: bearingId,
        message: 'Bearing verified authentic. Promotional reward points are currently inactive for this account profile.',
      );
    }

    if (claimedList.contains(bearingId)) {
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

    final curBal = prefs.getInt('${_prefKeyOfflineWallet}balance_$userEmail') ?? 0;
    final totalEarned = prefs.getInt('${_prefKeyOfflineWallet}earned_$userEmail') ?? 0;

    final newBal = curBal + points;
    await prefs.setInt('${_prefKeyOfflineWallet}balance_$userEmail', newBal);
    await prefs.setInt('${_prefKeyOfflineWallet}earned_$userEmail', totalEarned + points);

    return RewardClaimResult(
      rewardAwarded: true,
      bearingId: bearingId,
      pointsEarned: points,
      amountInr: inr,
      rateDisplay: '${settings.pointsBaseUnit} Points = ₹${settings.inrPerBaseUnit.toStringAsFixed(2)}',
      newBalance: newBal,
      message: 'First-scan reward claimed!',
    );
  }

  static Future<RewardProfile> _localGetUserRewardProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = await fetchRewardSettings();
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
      'status': 'PENDING',
      'created_at': DateTime.now().toIso8601String(),
      'user_email': userEmail,
      'user_name': AuthController.instance.userName ?? userEmail.split('@').first,
    };

    final raw = prefs.getString(_prefKeyOfflineRedemptions);
    List<dynamic> list = raw != null ? jsonDecode(raw) : [];
    list.insert(0, newReq);
    await prefs.setString(_prefKeyOfflineRedemptions, jsonEncode(list));

    return {
      'success': true,
      'request_number': reqNum,
      'points_requested': points,
      'amount_in_inr': points * mult,
      'status': 'PENDING',
      'message': 'Redemption request submitted successfully!',
    };
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
    } else if (id.contains('://')) {
      final uri = Uri.tryParse(id);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        id = uri.pathSegments.last.split('?').first;
      }
    }
    return id.toUpperCase().trim();
  }
}
