import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_service.dart';
import '../auth/auth_controller.dart';
import '../../features/rewards/data/services/reward_service.dart';

/// Result returned after checking or recording a false QR code scan
class FraudCheckResult {
  final bool isLimitReached;
  final bool isWarning;
  final int currentCount;
  final int limit;
  final String warningMessage;

  const FraudCheckResult({
    required this.isLimitReached,
    required this.isWarning,
    required this.currentCount,
    required this.limit,
    required this.warningMessage,
  });

  bool get isLocked => isLimitReached;
  bool get hasWarning => isWarning || isLimitReached;
  int get invalidCount => currentCount;
  int get fraudLimit => limit;
}

/// Pivot Bearings India - Anti-Fraud & Counterfeit Shield Service
///
/// Enforces the Admin Panel's Anti-Fraud Scan Limit against invalid/false QR codes:
/// 1. Reads dynamic fraud scan threshold set by Admin in RewardProgramSettings.
/// 2. Records false QR code scan attempts per user/device.
/// 3. Warns the user on false scans: "You must not scan any false QR codes from now else your ID will be banned".
/// 4. When fraud limit is reached (e.g. 3 false scans), locks the scanner and prevents further scanning.
class AntiFraudService {
  static const String _prefKeyFraudCountPrefix = 'pbi_fraud_invalid_count_';
  static const String _prefKeyFraudLimitOverride = 'pbi_antifraud_scan_limit_override';

  /// Returns today's date key string (YYYY-MM-DD)
  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Current user identifier for fraud tracking
  static String _userKey() {
    final uid = AuthController.instance.userId ??
        AuthController.instance.userEmail?.toLowerCase() ??
        SupabaseService.currentUserId ??
        'default_scanner';
    return uid.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
  }

  /// Fetches the configured fraud limit (defaults to 50, or whatever Admin set e.g. 3)
  static Future<int> getFraudLimit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final override = prefs.getInt(_prefKeyFraudLimitOverride);
      if (override != null && override > 0) {
        return override;
      }

      final settings = await RewardService.fetchRewardSettings();
      if (settings.dailyMaxScans > 0) {
        return settings.dailyMaxScans;
      }
    } catch (_) {}

    return 3; // Default safe limit if not set
  }

  /// Sets or updates the fraud limit (called from Admin Panel)
  static Future<void> setFraudLimit(int limit) async {
    final safeLimit = limit > 0 ? limit : 3;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeyFraudLimitOverride, safeLimit);
  }

  /// Gets the count of invalid/false QR scans recorded today
  static Future<int> getTodayInvalidScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefKeyFraudCountPrefix${_userKey()}_${_todayKey()}';
    return prefs.getInt(key) ?? 0;
  }

  /// Checks if the scanner is currently locked due to reaching the fraud limit
  static Future<bool> isScannerLocked() async {
    final count = await getTodayInvalidScanCount();
    final limit = await getFraudLimit();
    return count >= limit;
  }

  /// Retrieves current fraud status without recording a scan
  static Future<FraudCheckResult> getFraudLockStatus() async {
    final count = await getTodayInvalidScanCount();
    final limit = await getFraudLimit();
    final isLimitReached = count >= limit;
    final isWarning = count >= (limit - 1);

    String msg;
    if (isLimitReached) {
      msg = 'ANTI-FRAUD VIOLATION: You have scanned $count false QR codes, exceeding the fraud limit ($limit). You are now unable to scan QR codes. You must not scan any false QR codes from now else your ID will be banned!';
    } else if (count == limit - 1) {
      msg = 'FINAL WARNING: You have scanned $count of $limit allowed false QR codes. You must not scan any false QR codes from now else your ID will be banned!';
    } else {
      msg = 'False QR code detected ($count/$limit). You must not scan any false QR codes from now else your ID will be banned!';
    }

    return FraudCheckResult(
      isLimitReached: isLimitReached,
      isWarning: isWarning,
      currentCount: count,
      limit: limit,
      warningMessage: msg,
    );
  }

  /// Records an invalid/false QR scan attempt, logs telemetry, and evaluates limits
  static Future<FraudCheckResult> recordInvalidScan({
    String? rawPayload,
    String? scannedPayload,
    String? reason,
    String? sourceModule,
  }) async {
    final payload = (rawPayload ?? scannedPayload ?? '').trim();
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefKeyFraudCountPrefix${_userKey()}_${_todayKey()}';
    final current = prefs.getInt(key) ?? 0;
    final newCount = current + 1;
    await prefs.setInt(key, newCount);

    final limit = await getFraudLimit();
    final isLimitReached = newCount >= limit;
    final isWarning = newCount >= (limit - 1);

    // Telemetry log to Supabase if connected
    if (SupabaseService.isInitialized) {
      try {
        SupabaseService.client.from('scan_records').insert({
          'scanned_payload': payload,
          'is_valid': false,
          'scanned_by': SupabaseService.currentUserId,
          'notes': 'False QR code attempt $newCount of $limit in ${sourceModule ?? "SCANNER"}${reason != null ? " ($reason)" : ""}',
          'scan_timestamp': DateTime.now().toIso8601String(),
        }).then((_) {}).catchError((_) {});
      } catch (_) {}
    }

    String msg;
    if (isLimitReached) {
      msg = 'ANTI-FRAUD VIOLATION: You have scanned $newCount false QR codes, exceeding the fraud limit ($limit). You are now unable to scan QR codes. You must not scan any false QR codes from now else your ID will be banned!';
    } else if (newCount == limit - 1) {
      msg = 'FINAL WARNING: You have scanned $newCount of $limit allowed false QR codes. You must not scan any false QR codes from now else your ID will be banned!';
    } else {
      msg = 'False QR code detected ($newCount/$limit). You must not scan any false QR codes from now else your ID will be banned!';
    }

    debugPrint('AntiFraud: recorded false scan $newCount / $limit (Locked: $isLimitReached)');

    return FraudCheckResult(
      isLimitReached: isLimitReached,
      isWarning: isWarning,
      currentCount: newCount,
      limit: limit,
      warningMessage: msg,
    );
  }

  /// Clears the invalid scan count (for admin testing or unblocking)
  static Future<void> resetInvalidScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefKeyFraudCountPrefix${_userKey()}_${_todayKey()}';
    await prefs.remove(key);
  }
}
