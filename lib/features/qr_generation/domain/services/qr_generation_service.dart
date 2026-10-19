import 'bearing_encryption_key_service.dart';

/// QR Payload Format for Pivot Bearings India
/// Standard: Pure alphanumeric code & characters (e.g. `PB-6204-XA`, `PB-6204-8Z`)
class QrPayload {
  final String bearingId;
  final String batchCode;
  final String modelNumber;
  final int warrantyMonths;

  const QrPayload({
    required this.bearingId,
    required this.batchCode,
    this.modelNumber = 'PBI-6204-ZZ',
    this.warrantyMonths = 6,
  });

  /// Formats the payload for embedding into the physical QR matrix (strictly pure code & characters, no URLs)
  String toEncodedUri() {
    return bearingId;
  }

  /// Parses a scanned QR payload or raw bearing code
  static QrPayload? parse(String rawScanned) {
    var trimmed = rawScanned.trim();
    if (trimmed.isEmpty) return null;

    // Strip any URL prefix if present so only pure code remains
    if (trimmed.contains('/pbi/')) {
      final parts = trimmed.split('/pbi/');
      if (parts.length > 1) {
        trimmed = parts[1].split('?').first.split('&').first;
      }
    } else if (trimmed.contains('://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        trimmed = uri.pathSegments.last.split('?').first;
      }
    }

    // Direct part ID support (e.g. "PB-9402-XJ")
    final cleaned = trimmed.toUpperCase();
    return QrPayload(
      bearingId: cleaned,
      batchCode: 'BATCH-2026-OCT-A',
    );
  }
}

/// Service for generating batch serial codes and QR payloads
class QrGenerationService {
  /// Generates a sequential batch of bearing IDs (legacy)
  static List<String> generateBatchSerialIds({
    required String prefix,
    required int count,
    int startSequence = 1,
  }) {
    final List<String> ids = [];
    for (int i = 0; i < count; i++) {
      final seq = (startSequence + i).toString().padLeft(4, '0');
      ids.add('$prefix-$seq-XJ');
    }
    return ids;
  }

  /// Generates a batch of cryptographic encryption keys for bearings
  static List<String> generateCryptographicBatchKeys({
    required String modelNumber,
    required int count,
    String? batchCode,
    int warrantyMonths = 6,
  }) {
    final List<String> keys = [];
    for (int i = 0; i < count; i++) {
      keys.add(BearingEncryptionKeyService.generateKey(
        modelNumber: modelNumber,
        batchCode: batchCode,
        sequenceIndex: i,
        warrantyMonths: warrantyMonths,
      ));
    }
    return keys;
  }
}
