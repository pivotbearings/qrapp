enum VerificationEventType {
  inEvent,
  outEvent,
}

/// Pivot Bearings India - Authoritative Verification Event Log
class VerificationEvent {
  final String id;
  final String bearingId;
  final VerificationEventType eventType;
  final DateTime serverTimestamp;
  final String? proofImageHash;
  final String? operatorId;
  final String? facilityNote;

  const VerificationEvent({
    required this.id,
    required this.bearingId,
    required this.eventType,
    required this.serverTimestamp,
    this.proofImageHash,
    this.operatorId,
    this.facilityNote,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bearing_id': bearingId,
      'event_type': eventType.name,
      'server_timestamp': serverTimestamp.toIso8601String(),
      'proof_image_hash': proofImageHash,
      'operator_id': operatorId,
      'facility_note': facilityNote,
    };
  }

  factory VerificationEvent.fromJson(Map<String, dynamic> json) {
    return VerificationEvent(
      id: json['id'] as String,
      bearingId: json['bearing_id'] as String,
      eventType: VerificationEventType.values.firstWhere(
        (e) => e.name == json['event_type'],
        orElse: () => VerificationEventType.inEvent,
      ),
      serverTimestamp: DateTime.parse(json['server_timestamp'] as String),
      proofImageHash: json['proof_image_hash'] as String?,
      operatorId: json['operator_id'] as String?,
      facilityNote: json['facility_note'] as String?,
    );
  }
}
