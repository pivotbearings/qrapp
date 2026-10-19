/// Pivot Bearings India - Historical Cycle Record
class BearingCycleRecord {
  final int cycleNumber;
  final DateTime inTimestamp;
  final DateTime? outTimestamp;
  final int? durationSeconds;

  const BearingCycleRecord({
    required this.cycleNumber,
    required this.inTimestamp,
    this.outTimestamp,
    this.durationSeconds,
  });

  factory BearingCycleRecord.fromJson(Map<String, dynamic> json) {
    return BearingCycleRecord(
      cycleNumber: (json['cycle_number'] as num?)?.toInt() ?? 1,
      inTimestamp: json['in_timestamp'] != null
          ? DateTime.tryParse(json['in_timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
      outTimestamp: json['out_timestamp'] != null
          ? DateTime.tryParse(json['out_timestamp'].toString())
          : null,
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
    );
  }

  String get formattedDuration {
    if (durationSeconds == null || durationSeconds! <= 0) return 'In Progress';
    final sec = durationSeconds!;
    final days = sec ~/ 86400;
    final hours = (sec % 86400) ~/ 3600;
    final minutes = (sec % 3600) ~/ 60;

    if (days > 0) {
      if (hours > 0) {
        return '$days ${days == 1 ? "day" : "days"}, $hours ${hours == 1 ? "hr" : "hrs"}';
      }
      return '$days ${days == 1 ? "day" : "days"}';
    } else if (hours > 0) {
      if (minutes > 0) {
        return '$hours ${hours == 1 ? "hr" : "hrs"}, $minutes min';
      }
      return '$hours ${hours == 1 ? "hr" : "hrs"}';
    } else if (minutes > 0) {
      return '$minutes min';
    } else {
      return '$sec sec';
    }
  }
}

/// Result returned from Track Your Bearing scan
class BearingTrackResult {
  final bool isValid;
  final String action; // 'BEARING_IN' or 'BEARING_OUT'
  final String? bearingId;
  final String? modelNumber;
  final String? batchCode;
  final String? plantLocation;
  final int cycleNumber;
  final DateTime? inTimestamp;
  final DateTime? outTimestamp;
  final int durationSeconds;
  final int durationDays;
  final int durationHours;
  final int durationMinutes;
  final String? message;
  final List<BearingCycleRecord> lifecycleHistory;
  final String? rawPayload;

  const BearingTrackResult({
    required this.isValid,
    required this.action,
    this.bearingId,
    this.modelNumber,
    this.batchCode,
    this.plantLocation,
    this.cycleNumber = 1,
    this.inTimestamp,
    this.outTimestamp,
    this.durationSeconds = 0,
    this.durationDays = 0,
    this.durationHours = 0,
    this.durationMinutes = 0,
    this.message,
    this.lifecycleHistory = const [],
    this.rawPayload,
  });

  bool get isBearingIn => isValid && action == 'BEARING_IN';
  bool get isBearingOut => isValid && action == 'BEARING_OUT';
  /// Terminal state: bearing permanently decommissioned, no further scans allowed
  bool get isAlreadyOut => isValid && action == 'ALREADY_OUT';
  bool get isInvalid => !isValid;

  factory BearingTrackResult.fromJson(Map<String, dynamic> json, {String? rawPayload}) {
    final historyList = (json['lifecycle_history'] as List<dynamic>?)
            ?.map((e) => BearingCycleRecord.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        [];

    final durSec = (json['duration_seconds'] as num?)?.toInt() ?? 0;
    final durDays = (json['duration_days'] as num?)?.toInt() ?? (durSec ~/ 86400);
    final durHours = (json['duration_hours'] as num?)?.toInt() ?? ((durSec % 86400) ~/ 3600);
    final durMinutes = (json['duration_minutes'] as num?)?.toInt() ?? ((durSec % 3600) ~/ 60);

    return BearingTrackResult(
      isValid: json['is_valid'] == true,
      action: json['action']?.toString() ?? 'INVALID',
      bearingId: json['bearing_id']?.toString() ?? json['scanned_id']?.toString(),
      modelNumber: json['model_number']?.toString() ?? 'PBI-6204-ZZ',
      batchCode: json['batch_code']?.toString() ?? 'BATCH-ACTIVE',
      plantLocation: json['plant_location']?.toString() ?? 'Plant 02 — Chakan Industrial Complex',
      cycleNumber: (json['cycle_number'] as num?)?.toInt() ?? 1,
      inTimestamp: json['in_timestamp'] != null
          ? DateTime.tryParse(json['in_timestamp'].toString())
          : null,
      outTimestamp: json['out_timestamp'] != null
          ? DateTime.tryParse(json['out_timestamp'].toString())
          : null,
      durationSeconds: durSec,
      durationDays: durDays,
      durationHours: durHours,
      durationMinutes: durMinutes,
      message: json['message']?.toString(),
      lifecycleHistory: historyList,
      rawPayload: rawPayload,
    );
  }

  factory BearingTrackResult.invalid({String? rawPayload, String? message}) {
    return BearingTrackResult(
      isValid: false,
      action: 'INVALID',
      bearingId: rawPayload,
      message: message ?? 'Invalid Bearing Code. Bearing Authenticity Could Not Be Verified.',
      rawPayload: rawPayload,
    );
  }

  /// Terminal: bearing has been permanently marked out, no further scans allowed in Track module
  factory BearingTrackResult.alreadyOut({
    required String bearingId,
    DateTime? inTimestamp,
    DateTime? outTimestamp,
    String? modelNumber,
    String? message,
    String? rawPayload,
  }) {
    return BearingTrackResult(
      isValid: true,
      action: 'ALREADY_OUT',
      bearingId: bearingId,
      modelNumber: modelNumber,
      inTimestamp: inTimestamp,
      outTimestamp: outTimestamp,
      message: message ?? 'This bearing has already been marked out and cannot be tracked again.',
      rawPayload: rawPayload,
    );
  }

  /// Exact format: "You used this bearing for 5 days."
  String get formattedUsageDuration {
    if (durationDays > 0) {
      if (durationHours > 0 && durationMinutes > 0) {
        return 'You used this bearing for $durationDays ${durationDays == 1 ? "day" : "days"}, $durationHours ${durationHours == 1 ? "hour" : "hours"}, and $durationMinutes ${durationMinutes == 1 ? "minute" : "minutes"}.';
      } else if (durationHours > 0) {
        return 'You used this bearing for $durationDays ${durationDays == 1 ? "day" : "days"} and $durationHours ${durationHours == 1 ? "hour" : "hours"}.';
      } else {
        return 'You used this bearing for $durationDays ${durationDays == 1 ? "day" : "days"}.';
      }
    } else if (durationHours > 0) {
      if (durationMinutes > 0) {
        return 'You used this bearing for $durationHours ${durationHours == 1 ? "hour" : "hours"} and $durationMinutes ${durationMinutes == 1 ? "minute" : "minutes"}.';
      } else {
        return 'You used this bearing for $durationHours ${durationHours == 1 ? "hour" : "hours"}.';
      }
    } else if (durationMinutes > 0) {
      return 'You used this bearing for $durationMinutes ${durationMinutes == 1 ? "minute" : "minutes"}.';
    } else {
      final sec = durationSeconds > 0 ? durationSeconds : 1;
      return 'You used this bearing for $sec ${sec == 1 ? "second" : "seconds"}.';
    }
  }
}
