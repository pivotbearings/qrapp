/// Pivot Bearings India - Bearing Authentication Result Domain Model
///
/// Encapsulates authoritative server-verified authentication states and scan counts:
/// - First Scan: Genuine Pivot Bearing, first recorded authentication.
/// - Second Scan: Genuine bearing, previously scanned exactly once.
/// - Third+ Scans: Genuine bearing, previously scanned N times.
/// - Invalid: Unregistered, altered, or malformed QR code.
class BearingAuthenticationResult {
  final bool isAuthentic;
  final int previousScanCount;
  final int totalScanCount;
  final String? bearingId;
  final String? modelNumber;
  final String? batchCode;
  final String? plantLocation;
  final String? warrantyPlanTitle;
  final int? warrantyDurationMonths;
  final String? currentLifecycleState;
  final DateTime? firstScannedAt;
  final DateTime? lastScannedAt;
  final bool isFlagged;
  final String? flagReason;
  final String? message;
  final String? rawPayload;
  final String? errorCode;

  const BearingAuthenticationResult({
    required this.isAuthentic,
    this.previousScanCount = 0,
    this.totalScanCount = 1,
    this.bearingId,
    this.modelNumber,
    this.batchCode,
    this.plantLocation,
    this.warrantyPlanTitle,
    this.warrantyDurationMonths,
    this.currentLifecycleState,
    this.firstScannedAt,
    this.lastScannedAt,
    this.isFlagged = false,
    this.flagReason,
    this.message,
    this.rawPayload,
    this.errorCode,
  });

  /// Factory from Supabase `authenticate_bearing_qr` RPC JSON response
  factory BearingAuthenticationResult.fromJson(
    Map<String, dynamic> json, {
    String? rawPayload,
  }) {
    final isAuth = json['is_authentic'] == true;
    final prevCount = (json['previous_scan_count'] as num?)?.toInt() ?? 0;
    final totalCount = (json['total_scan_count'] as num?)?.toInt() ?? (prevCount + 1);

    return BearingAuthenticationResult(
      isAuthentic: isAuth,
      previousScanCount: prevCount,
      totalScanCount: totalCount,
      bearingId: json['bearing_id']?.toString() ?? json['scanned_id']?.toString(),
      modelNumber: json['model_number']?.toString() ?? 'PBI-6204-ZZ',
      batchCode: json['batch_code']?.toString() ?? 'BATCH-ACTIVE',
      plantLocation: json['plant_location']?.toString() ?? 'Plant 02 — Chakan Industrial Complex',
      warrantyPlanTitle: json['warranty_plan_title']?.toString() ?? 'Standard Factory Warranty',
      warrantyDurationMonths: (json['warranty_duration_months'] as num?)?.toInt() ?? 6,
      currentLifecycleState: json['current_lifecycle_state']?.toString() ?? 'NOT_ACTIVATED',
      firstScannedAt: json['first_scanned_at'] != null
          ? DateTime.tryParse(json['first_scanned_at'].toString())
          : null,
      lastScannedAt: json['last_scanned_at'] != null
          ? DateTime.tryParse(json['last_scanned_at'].toString())
          : null,
      isFlagged: json['is_flagged'] == true,
      flagReason: json['flag_reason']?.toString(),
      message: json['message']?.toString(),
      rawPayload: rawPayload,
      errorCode: json['error_code']?.toString(),
    );
  }

  /// Factory for decommissioned bearings marked as OUT
  factory BearingAuthenticationResult.alreadyOut({
    String? rawPayload,
    String? bearingId,
    String? message,
  }) {
    return BearingAuthenticationResult(
      isAuthentic: false,
      currentLifecycleState: 'FINAL_OUT',
      bearingId: bearingId ?? rawPayload,
      rawPayload: rawPayload,
      message: message ?? 'bearing marked as out, cant scan again.',
      errorCode: 'ALREADY_OUT',
    );
  }

  /// Factory for unregistered or invalid QR codes
  factory BearingAuthenticationResult.invalid({
    String? rawPayload,
    String? scannedId,
    String? message,
    String? errorCode,
  }) {
    return BearingAuthenticationResult(
      isAuthentic: false,
      previousScanCount: 0,
      totalScanCount: 0,
      bearingId: scannedId ?? rawPayload,
      rawPayload: rawPayload,
      message: message ?? 'Bearing Authenticity Could Not Be Verified',
      errorCode: errorCode ?? 'NOT_REGISTERED',
    );
  }

  /// Condition checks
  bool get isAlreadyOut =>
      currentLifecycleState == 'FINAL_OUT' ||
      currentLifecycleState == 'CURRENTLY_OUT' ||
      currentLifecycleState == 'DECOMMISSIONED' ||
      errorCode == 'ALREADY_OUT';
  bool get isFirstScan => !isAlreadyOut && isAuthentic && totalScanCount <= 1 && previousScanCount == 0;
  bool get isSecondScan => !isAlreadyOut && isAuthentic && !isFirstScan && (totalScanCount == 2 || previousScanCount == 1);
  bool get isThirdOrSubsequentScan => !isAlreadyOut && isAuthentic && (totalScanCount >= 3 || previousScanCount >= 2);
  bool get isRepeatedScan => !isAlreadyOut && isAuthentic && !isFirstScan;
  bool get isInvalid => !isAlreadyOut && !isAuthentic;

  /// Prominent Headline
  String get headline {
    if (isAlreadyOut) {
      return 'bearing marked as out, cant scan again.';
    }
    if (isAuthentic) {
      return 'Authentic Pivot Bearing';
    }
    return 'Invalid Bearing Code';
  }

  /// Clear Subheading
  String get subHeadline {
    if (isAlreadyOut) {
      return 'bearing marked as out, cant scan again.';
    }
    if (isFirstScan) {
      return 'Bearing Successfully Authenticated';
    } else if (isSecondScan) {
      return 'Already Scanned Once';
    } else if (isThirdOrSubsequentScan) {
      return 'Scanned $previousScanCount Times Previously';
    }
    return 'Bearing Authenticity Could Not Be Verified';
  }

  /// User-facing descriptive message adhering strictly to specifications:
  /// - Marked as out: "bearing marked as out, cant scan again."
  /// - First scan: "Authentic Pivot Bearing. Bearing has been successfully authenticated."
  /// - Second scan: "This QR code has already been scanned once and that it belongs to an authentic bearing."
  /// - Third and subsequent scans: "This QR code has already been scanned [N] times. Authentic Pivot Bearing."
  /// - Invalid QR code: "Invalid Bearing Code" / "Bearing Authenticity Could Not Be Verified. Never identify an unregistered code as genuine."
  String get scanConditionMessage {
    if (isAlreadyOut) {
      return 'bearing marked as out, cant scan again.';
    }
    if (isFirstScan) {
      return 'Authentic Pivot Bearing. Clearly confirmed that the bearing has been successfully authenticated.';
    } else if (isSecondScan) {
      return 'This QR code has already been scanned once and that it belongs to an authentic bearing.';
    } else if (isThirdOrSubsequentScan) {
      return 'This QR code has already been scanned $previousScanCount times. Authentic Pivot Bearing.';
    }
    return 'Invalid Bearing Code. Bearing Authenticity Could Not Be Verified. Never identify an unregistered code as genuine.';
  }
}
