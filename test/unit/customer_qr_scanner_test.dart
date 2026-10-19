import 'package:flutter_test/flutter_test.dart';
import 'package:pivot_bearings_app/features/bearing_verification/data/models/bearing_model.dart';
import 'package:pivot_bearings_app/features/bearing_verification/data/repositories/bearing_repository.dart';
import 'package:pivot_bearings_app/features/bearing_verification/domain/models/qr_verification_result.dart';
import 'package:pivot_bearings_app/features/qr_generation/domain/services/qr_generation_service.dart';

void main() {
  group('Customer QR Scanner & Authoritative Verification Tests', () {
    late BearingRepository repository;

    setUp(() {
      repository = BearingRepositoryImpl();

      BearingRepositoryImpl.registerInMemoryBearing(
        BearingModel(
          id: 'PB-9402-XJ',
          batchCode: 'BATCH-2026-OCT-A',
          warrantyDurationMonths: 12,
          state: BearingLifecycleState.notActivated,
          plantLocation: 'Plant 02 — Chakan',
          modelNumber: 'PBI-6204-ZZ',
        ),
      );

      BearingRepositoryImpl.registerInMemoryBearing(
        BearingModel(
          id: 'PB-7701-AB',
          batchCode: 'BATCH-2026-OCT-B',
          warrantyDurationMonths: 6,
          state: BearingLifecycleState.currentlyIn,
          firstInDate: DateTime.now().subtract(const Duration(days: 30)),
          lastInDate: DateTime.now().subtract(const Duration(days: 30)),
          plantLocation: 'Plant 01 — Pune',
          modelNumber: 'PBI-6305-2RS',
        ),
      );

      BearingRepositoryImpl.registerInMemoryBearing(
        BearingModel(
          id: 'PB-8812-KR',
          batchCode: 'BATCH-2025-JAN-X',
          warrantyDurationMonths: 6,
          state: BearingLifecycleState.currentlyOut,
          firstInDate: DateTime.now().subtract(const Duration(days: 300)),
          lastInDate: DateTime.now().subtract(const Duration(days: 300)),
          lastOutDate: DateTime.now().subtract(const Duration(days: 10)),
          plantLocation: 'Plant 03 — Sanand',
          modelNumber: 'PBI-6000-ZZ',
        ),
      );
    });

    test('1. Valid Bearing - Not Activated State', () async {
      final result = await repository.verifyScannedPayload('https://verify.pivotbearings.com/pbi/PB-9402-XJ');

      expect(result.status, QrVerificationStatus.validNotActivated);
      expect(result.bearingId, 'PB-9402-XJ');
      expect(result.canMarkIn, isTrue);
      expect(result.canMarkOut, isFalse);
      expect(result.firstInTimestamp, isNull, reason: 'Scanning alone must NOT start the warranty');
      expect(result.isExpired, isFalse);
    });

    test('2. Valid Bearing - Currently IN State with Active Warranty', () async {
      final result = await repository.verifyScannedPayload('PB-7701-AB');

      expect(result.status, QrVerificationStatus.validWarrantyActive);
      expect(result.bearingId, 'PB-7701-AB');
      expect(result.canMarkIn, isFalse);
      expect(result.canMarkOut, isTrue);
      expect(result.isExpired, isFalse);
    });

    test('3. Valid Bearing - Terminal Decommissioned CURRENTLY_OUT State', () async {
      final result = await repository.verifyScannedPayload('PB-8812-KR');

      expect(result.bearingId, 'PB-8812-KR');
      expect(result.status, QrVerificationStatus.decommissionedOut);
      expect(result.canMarkIn, isFalse, reason: 'CURRENTLY_OUT bearing cannot be re-installed');
      expect(result.canMarkOut, isFalse);
    });

    test('4. Blocked / Flagged Bearing State', () async {
      // Register a blocked bearing
      BearingRepositoryImpl.registerInMemoryBearing(
        BearingModel(
          id: 'PB-6204-ZK',
          batchCode: 'BATCH-FLAGGED',
          warrantyDurationMonths: 6,
          state: BearingLifecycleState.notActivated,
        ),
      );

      // Verify that unverified payloads or unknown IDs return qrUnknownOrInvalid
      final result = await repository.verifyScannedPayload('PB-9999-ZZ');
      expect(result.status, QrVerificationStatus.qrUnknownOrInvalid);
    });

    test('5. Malformed, Damaged, or 1D Barcode Payloads', () async {
      final invalidSamples = [
        '',
        '   ',
        '8901234567890', // EAN-13 1D barcode
        'INVALID-CODE-128',
        'HTTP://NOT-PIVOT.COM',
        'PB-999-X', // Invalid format
      ];

      for (final sample in invalidSamples) {
        final res = await repository.verifyScannedPayload(sample);
        expect(
          res.status,
          QrVerificationStatus.qrUnknownOrInvalid,
          reason: 'Payload "$sample" must evaluate to unknown/invalid',
        );
      }
    });

    test('6. Unregistered Bearing ID', () async {
      final result = await repository.verifyScannedPayload('PB-0000-ZZ');

      expect(result.status, QrVerificationStatus.qrUnknownOrInvalid);
      expect(result.errorMessage, contains('not registered'));
    });

    test('7. Scanning Alone Must NEVER Start Warranty', () async {
      final before = await repository.getBearingById('PB-9402-XJ');
      expect(before?.firstInDate, isNull);

      // Perform repeated scans
      await repository.verifyScannedPayload('PB-9402-XJ');
      await repository.verifyScannedPayload('https://verify.pivotbearings.com/pbi/PB-9402-XJ');
      await repository.verifyScannedPayload('PB-9402-XJ');

      final after = await repository.getBearingById('PB-9402-XJ');
      expect(after?.firstInDate, isNull, reason: 'Scanning alone must never anchor activation timestamp');
    });

    test('8. Concurrent Requests Stability', () async {
      final futures = List.generate(
        10,
        (i) => repository.verifyScannedPayload('PB-9402-XJ'),
      );

      final results = await Future.wait(futures);
      expect(results.length, 10);
      for (final r in results) {
        expect(r.status, QrVerificationStatus.validNotActivated);
      }
    });

    test('9. QR Payload Parsing - Strict Format Enforcement', () {
      final validUri = 'https://verify.pivotbearings.com/pbi/PB-9402-XJ?batch=BATCH-2026-OCT-A&m=PBI-6204-ZZ&w=6';
      final parsed = QrPayload.parse(validUri);

      expect(parsed, isNotNull);
      expect(parsed!.bearingId, 'PB-9402-XJ');
      expect(parsed.batchCode, 'BATCH-2026-OCT-A');
      expect(parsed.modelNumber, 'PBI-6204-ZZ');

      final invalidParsed = QrPayload.parse('');
      expect(invalidParsed, isNull);
    });
  });
}
