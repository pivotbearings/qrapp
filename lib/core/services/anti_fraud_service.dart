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
    this.isLimitReached = false,
    this.isWarning = false,
    this.currentCount = 0,
    this.limit = 999999,
    this.warningMessage = '',
  });

  bool get isLocked => false;
  bool get hasWarning => false;
  int get invalidCount => currentCount;
  int get fraudLimit => limit;
}

/// Pivot Bearings India - Anti-Fraud & Counterfeit Shield Service
///
/// Records invalid scan telemetry for security audits, but NEVER locks the scanner
/// or limits user scanning. All QR scanning is 100% unlimited.
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

  /// Unlimited scan threshold (no scan limitation)
  static Future<int> getFraudLimit() async {
    return 999999;
  }

  /// Sets or updates the fraud limit (kept for interface compatibility)
  static Future<void> setFraudLimit(int limit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyFraudLimitOverride);
  }

  /// Gets the count of invalid/false QR scans recorded today
  static Future<int> getTodayInvalidScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefKeyFraudCountPrefix${_userKey()}_${_todayKey()}';
    return prefs.getInt(key) ?? 0;
  }

  /// Scanner is NEVER locked: all scanning is 100% unlimited
  static Future<bool> isScannerLocked() async {
    return false;
  }

  /// Retrieves current fraud status without locking the scanner
  static Future<FraudCheckResult> getFraudLockStatus() async {
    final count = await getTodayInvalidScanCount();
    return FraudCheckResult(
      isLimitReached: false,
      isWarning: false,
      currentCount: count,
      limit: 999999,
      warningMessage: '',
    );
  }

  /// Records an invalid/false QR scan attempt, logs telemetry, but never locks the scanner
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

    // Telemetry log to Supabase if connected
    if (SupabaseService.isInitialized) {
      try {
        SupabaseService.client.from('scan_records').insert({
          'scanned_payload': payload,
          'is_valid': false,
          'scanned_by': SupabaseService.currentUserId,
          'notes': 'Unregistered QR code attempt $newCount in ${sourceModule ?? "SCANNER"}${reason != null ? " ($reason)" : ""}',
          'scan_timestamp': DateTime.now().toIso8601String(),
        }).then((_) {}).catchError((_) {});
      } catch (_) {}
    }

    return FraudCheckResult(
      isLimitReached: false,
      isWarning: false,
      currentCount: newCount,
      limit: 999999,
      warningMessage: '',
    );
  }

  /// Clears the invalid scan count (for admin testing or unblocking)
  static Future<void> resetInvalidScanCount() async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefKeyFraudCountPrefix${_userKey()}_${_todayKey()}';
    await prefs.remove(key);
    await prefs.remove(_prefKeyFraudLimitOverride);
  }
}
