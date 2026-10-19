import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../qr_generation/domain/services/bearing_encryption_key_service.dart';
import '../../../qr_generation/domain/services/qr_generation_service.dart';

/// QR Detection & Validation Service
class QrScannerService {
  /// Extracts the bearing ID and payload from a MobileScanner [BarcodeCapture]
  static QrPayload? extractPayloadFromBarcode(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty) return null;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        final payload = QrPayload.parse(raw);
        if (payload != null) {
          return payload;
        }
      }
    }
    return null;
  }

  /// Validates format of bearing identifier (cryptographic keys or legacy serials)
  static bool isValidBearingId(String id) {
    return BearingEncryptionKeyService.isValidKeyOrId(id);
  }
}
