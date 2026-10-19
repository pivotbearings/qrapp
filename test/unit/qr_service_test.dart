import 'package:flutter_test/flutter_test.dart';
import 'package:pivot_bearings_app/features/qr_generation/domain/services/qr_generation_service.dart';
import 'package:pivot_bearings_app/features/qr_scanner/domain/services/qr_scanner_service.dart';

void main() {
  group('QR Generation & Scanning Unit Tests', () {
    test('Encodes QrPayload to compliant URI', () {
      const payload = QrPayload(
        bearingId: 'PB-9402-XJ',
        batchCode: 'BATCH-2026-OCT-A',
        modelNumber: 'PBI-6204-ZZ',
        warrantyMonths: 6,
      );

      final uri = payload.toEncodedUri();
      expect(
        uri,
        equals(
          'https://verify.pivotbearings.com/pbi/PB-9402-XJ?batch=BATCH-2026-OCT-A&m=PBI-6204-ZZ&w=6',
        ),
      );
    });

    test('Parses encoded QR URI correctly', () {
      const uri =
          'https://verify.pivotbearings.com/pbi/PB-9402-XJ?batch=BATCH-2026-OCT-A&m=PBI-6204-ZZ&w=6';
      final parsed = QrPayload.parse(uri);

      expect(parsed, isNotNull);
      expect(parsed!.bearingId, equals('PB-9402-XJ'));
      expect(parsed.batchCode, equals('BATCH-2026-OCT-A'));
      expect(parsed.modelNumber, equals('PBI-6204-ZZ'));
      expect(parsed.warrantyMonths, equals(6));
    });

    test('Parses raw bearing ID string fallback correctly', () {
      final parsed = QrPayload.parse('PB-8812-KR');
      expect(parsed, isNotNull);
      expect(parsed!.bearingId, equals('PB-8812-KR'));
    });

    test('Generates sequential serial IDs in batch', () {
      final batch = QrGenerationService.generateBatchSerialIds(
        prefix: 'PB',
        count: 5,
        startSequence: 10,
      );

      expect(batch.length, equals(5));
      expect(batch[0], equals('PB-0010-XJ'));
      expect(batch[1], equals('PB-0011-XJ'));
      expect(batch[4], equals('PB-0014-XJ'));
    });

    test('Validates bearing ID format regex', () {
      expect(QrScannerService.isValidBearingId('PB-9402-XJ'), isTrue);
      expect(QrScannerService.isValidBearingId('PB-1234-AB'), isTrue);
      expect(QrScannerService.isValidBearingId('INVALID_ID'), isFalse);
    });
  });
}
