import '../services/warranty_calculator.dart';

/// Clear verification states returned by the authoritative backend
enum QrVerificationStatus {
  /// Valid cryptographic bearing, ready for first installation
  validNotActivated,

  /// Valid bearing with operating warranty active
  validWarrantyActive,

  /// Valid bearing, but warranty horizon has expired
  warrantyExpired,

  /// Bearing has been marked OUT and lifecycle has permanently ended (strictly no re-installation)
  decommissionedOut,

  /// Flagged/tampered bearing locked by Quality Directorate
  qrBlocked,

  /// Payload is malformed, damaged, or not in the registry
  qrUnknownOrInvalid,

  /// Device is disconnected or network request failed
  networkUnavailable,
}

/// Verification entity returned from Supabase `verify_bearing_qr` RPC
class QrVerificationResult {
  final QrVerificationStatus status;
  final String? bearingId;
  final String? batchCode;
  final String? plantLocation;
  final String? modelNumber;
  final String? warrantyPlanTitle;
  final int? warrantyDurationMonths;
  final String? currentLifecycleState;
  final DateTime? firstInTimestamp;
  final DateTime? warrantyExpiryTimestamp;
  final bool isExpired;
  final String? flagReason;
  final bool canMarkIn;
  final bool canMarkOut;
  final String? payloadHash;
  final String? errorMessage;

  const QrVerificationResult({
    required this.status,
    this.bearingId,
    this.batchCode,
    this.plantLocation,
    this.modelNumber,
    this.warrantyPlanTitle,
    this.warrantyDurationMonths,
    this.currentLifecycleState,
    this.firstInTimestamp,
    this.warrantyExpiryTimestamp,
    this.isExpired = false,
    this.flagReason,
    this.canMarkIn = false,
    this.canMarkOut = false,
    this.payloadHash,
    this.errorMessage,
  });

  factory QrVerificationResult.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['verification_status']?.toString() ?? json['status']?.toString();
    final lifecycleState = json['current_lifecycle_state']?.toString();
    final isCurrentlyOut = lifecycleState == 'CURRENTLY_OUT' ||
        lifecycleState == 'FINAL_OUT' ||
        lifecycleState == 'DECOMMISSIONED' ||
        rawStatus == 'DECOMMISSIONED_OUT' ||
        rawStatus == 'FINAL_OUT';

    QrVerificationStatus status;

    if (isCurrentlyOut) {
      status = QrVerificationStatus.decommissionedOut;
    } else {
      switch (rawStatus) {
        case 'VALID_NOT_ACTIVATED':
          status = QrVerificationStatus.validNotActivated;
          break;
        case 'VALID_WARRANTY_ACTIVE':
          status = QrVerificationStatus.validWarrantyActive;
          break;
        case 'WARRANTY_EXPIRED':
          status = QrVerificationStatus.warrantyExpired;
          break;
        case 'QR_BLOCKED':
        case 'FLAGGED':
          status = QrVerificationStatus.qrBlocked;
          break;
        case 'QR_UNKNOWN_OR_INVALID':
        case 'INVALID':
        default:
          status = QrVerificationStatus.qrUnknownOrInvalid;
          break;
      }
    }

      int? dur = json['warranty_duration_months'] is num
          ? (json['warranty_duration_months'] as num).toInt()
          : (json['duration_months'] is num ? (json['duration_months'] as num).toInt() : null);

      final firstIn = json['first_in_timestamp'] != null
          ? DateTime.tryParse(json['first_in_timestamp'].toString())
          : null;
      DateTime? expiry = json['warranty_expiry_timestamp'] != null
          ? DateTime.tryParse(json['warranty_expiry_timestamp'].toString())
          : null;

      if (dur == null && firstIn != null && expiry != null) {
        final diff = (expiry.year - firstIn.year) * 12 + (expiry.month - firstIn.month);
        if (diff > 0) dur = diff;
      }
      if (dur != null && firstIn != null) {
        expiry = WarrantyCalculator.calculateExpiryDate(firstInDate: firstIn, durationMonths: dur);
      }

      return QrVerificationResult(
        status: status,
        bearingId: json['bearing_id']?.toString() ?? json['scanned_id']?.toString(),
        batchCode: json['batch_code']?.toString(),
        plantLocation: json['plant_location']?.toString(),
        modelNumber: json['model_number']?.toString(),
        warrantyPlanTitle: json['warranty_plan_title']?.toString() ?? json['warranty_title']?.toString(),
        warrantyDurationMonths: dur,
        currentLifecycleState: lifecycleState,
        firstInTimestamp: firstIn,
        warrantyExpiryTimestamp: expiry,
      isExpired: json['is_expired'] == true,
      flagReason: json['flag_reason']?.toString(),
      canMarkIn: isCurrentlyOut ? false : (json['can_mark_in'] == true),
      canMarkOut: isCurrentlyOut ? false : (json['can_mark_out'] == true),
      payloadHash: json['payload_hash']?.toString(),
      errorMessage: json['message']?.toString(),
    );
  }

  factory QrVerificationResult.networkUnavailable({String? message}) {
    return QrVerificationResult(
      status: QrVerificationStatus.networkUnavailable,
      errorMessage: message ?? 'Network unavailable. Unable to contact authoritative registry.',
    );
  }

  factory QrVerificationResult.invalid({String? message, String? id}) {
    return QrVerificationResult(
      status: QrVerificationStatus.qrUnknownOrInvalid,
      bearingId: id,
      errorMessage: message ?? 'QR code damaged or not recognized.',
    );
  }

  String get displayTitle {
    switch (status) {
      case QrVerificationStatus.validNotActivated:
        return 'GENUINE PBI BEARING — NOT ACTIVATED';
      case QrVerificationStatus.validWarrantyActive:
        return 'GENUINE PBI BEARING — WARRANTY ACTIVE';
      case QrVerificationStatus.warrantyExpired:
        return 'GENUINE PBI BEARING — WARRANTY EXPIRED';
      case QrVerificationStatus.decommissionedOut:
        return 'GENUINE PBI BEARING — PERMANENTLY DECOMMISSIONED';
      case QrVerificationStatus.qrBlocked:
        return 'ALERT: BEARING BLOCKED / FLAGGED';
      case QrVerificationStatus.qrUnknownOrInvalid:
        return 'SECURITY ALERT: UNKNOWN / INVALID QR';
      case QrVerificationStatus.networkUnavailable:
        return 'OFFLINE / NETWORK UNAVAILABLE';
    }
  }
}
