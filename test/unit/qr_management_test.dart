import 'package:flutter_test/flutter_test.dart';
import 'package:pivot_bearings_app/core/services/qr_export_service.dart';
import 'package:pivot_bearings_app/features/qr_generation/data/repositories/qr_management_repository.dart';
import 'package:pivot_bearings_app/features/qr_generation/domain/services/bearing_encryption_key_service.dart';
import 'package:pivot_bearings_app/features/qr_generation/domain/services/qr_generation_service.dart';

void main() {
  group('QR Management & Generation Tests', () {
    late QrManagementRepository repository;

    setUp(() {
      repository = QrManagementRepository();
    });

    test('1. Uniqueness & Cryptographic Compliance in Batch Generation', () async {
      final result = await repository.generateQrBatch(
        batchCode: 'BATCH-TEST-2026',
        plantLocation: 'Plant 02 — Chakan',
        quantity: 100,
        modelNumber: 'PBI-6204-ZZ',
      );

      final rawIds = result['bearing_ids'] as List;
      final ids = rawIds.map((e) => e.toString()).toList();

      expect(ids.length, 100);

      // Verify every ID is unique (zero duplicate collisions)
      final uniqueSet = ids.toSet();
      expect(uniqueSet.length, 100);

      // Verify format conforms strictly to authentic cryptographic key
      for (final id in ids) {
        expect(BearingEncryptionKeyService.isValidKeyOrId(id), isTrue, reason: 'ID $id must match cryptographic key format');
        expect(BearingEncryptionKeyService.verifyTamperProofChecksum(id), isTrue, reason: 'ID $id must pass tamper-proof checksum');
      }
    });

    test('2. Large Batch Generation (500 items)', () async {
      final result = await repository.generateQrBatch(
        batchCode: 'BATCH-LARGE-500',
        plantLocation: 'Plant 01 — Sriperumbudur',
        quantity: 500,
      );

      final ids = (result['bearing_ids'] as List).map((e) => e.toString()).toList();
      expect(ids.length, 500);
      expect(ids.toSet().length, 500);
    });

    test('3. Invalid Quantity Rejection (< 1 or > 5000)', () async {
      expect(
        () => repository.generateQrBatch(
          batchCode: 'BATCH-INVALID',
          plantLocation: 'Chakan',
          quantity: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => repository.generateQrBatch(
          batchCode: 'BATCH-INVALID',
          plantLocation: 'Chakan',
          quantity: 5001,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('4. Mixed Bulk Warranty Assignment (e.g. 5 to 3M and 3 to 6M)', () async {
      final fiveBearings = ['PB-1001-A1', 'PB-1002-A2', 'PB-1003-A3', 'PB-1004-A4', 'PB-1005-A5'];
      final threeBearings = ['PB-2001-B1', 'PB-2002-B2', 'PB-2003-B3'];

      final List<Map<String, dynamic>> mixedAssignments = [];

      // 5 bearings assigned to 3 months (WP-3M)
      for (final id in fiveBearings) {
        mixedAssignments.add({
          'bearing_id': id,
          'warranty_plan_id': '11111111-1111-1111-1111-111111111111',
        });
      }

      // 3 bearings assigned to 6 months (WP-6M)
      for (final id in threeBearings) {
        mixedAssignments.add({
          'bearing_id': id,
          'warranty_plan_id': '22222222-2222-2222-2222-222222222222',
        });
      }

      final res = await repository.assignWarrantiesBulk(mixedAssignments);
      expect(res['success'], isTrue);
      expect(res['updated_count'], 8);
    });

    test('5. QR Generation & Printing Must NOT Start Warranty', () {
      final payload = QrPayload(
        bearingId: 'PB-9402-XJ',
        batchCode: 'BATCH-2026-OCT-A',
        modelNumber: 'PBI-6204-ZZ',
      );

      final encoded = payload.toEncodedUri();
      // Payload only identifies bearing and batch; never embeds an activation timestamp
      expect(encoded.contains('PB-9402-XJ'), isTrue);
      expect(encoded.contains('BATCH-2026-OCT-A'), isTrue);
      expect(encoded.contains('activated='), isFalse);
      expect(encoded.contains('expiry='), isFalse);
    });

    test('6. TXT Export for Notepad Formatting', () {
      final items = [
        {
          'bearing_id': 'PB-9402-XJ',
          'model_number': 'PBI-6204-ZZ',
          'duration_months': 6,
          'current_lifecycle_state': 'NOT_ACTIVATED',
          'payload_hash': 'SHA-256: 4F92E389B01A9402',
          'payload_value': 'https://verify.pivotbearings.com/pbi/PB-9402-XJ',
        },
      ];

      final txt = QrExportService.generateTxtManifest(
        batchCode: 'BATCH-2026-OCT-A',
        items: items,
      );

      expect(txt.contains('PIVOT BEARINGS INDIA'), isTrue);
      expect(txt.contains('PB-9402-XJ'), isTrue);
      expect(txt.contains('\r\n'), isTrue, reason: 'Must contain Windows CRLF line endings for Notepad');
      expect(txt.contains('VERIFICATION ENDPOINTS:'), isTrue);
    });

    test('7. CSV Export Formatting', () {
      final items = [
        {
          'bearing_id': 'PB-9402-XJ',
          'batch_code': 'BATCH-2026-OCT-A',
          'model_number': 'PBI-6204-ZZ',
          'duration_months': 6,
          'current_lifecycle_state': 'NOT_ACTIVATED',
          'is_flagged': false,
          'payload_value': 'https://verify.pivotbearings.com/pbi/PB-9402-XJ',
        },
      ];

      final csv = QrExportService.generateCsvManifest(items: items);
      expect(csv.startsWith('Bearing ID,Batch Code,Model Number'), isTrue);
      expect(csv.contains('PB-9402-XJ,BATCH-2026-OCT-A,PBI-6204-ZZ'), isTrue);
    });

    test('8. Word-Compatible DOC Export Formatting', () {
      final items = [
        {
          'bearing_id': 'PB-9402-XJ',
          'model_number': 'PBI-6204-ZZ',
          'duration_months': 6,
          'current_lifecycle_state': 'NOT_ACTIVATED',
          'is_flagged': false,
        },
      ];

      final doc = QrExportService.generateWordDoc(
        batchCode: 'BATCH-2026-OCT-A',
        items: items,
      );

      expect(doc.contains('urn:schemas-microsoft-com:office:word'), isTrue);
      expect(doc.contains('PIVOT BEARINGS INDIA'), isTrue);
      expect(doc.contains('PB-9402-XJ'), isTrue);
      expect(doc.contains('<table>'), isTrue);
    });

    test('9. QR Blocking & Flagging Invariants', () async {
      final blockResult = await repository.toggleQrBlock(
        bearingId: 'PB-9402-XJ',
        isFlagged: true,
        flagReason: 'Visual surface tampering detected',
      );

      expect(blockResult['success'], isTrue);
      expect(blockResult['is_flagged'], isTrue);
      expect(blockResult['flag_reason'], 'Visual surface tampering detected');

      // Unblock
      final unblockResult = await repository.toggleQrBlock(
        bearingId: 'PB-9402-XJ',
        isFlagged: false,
      );

      expect(unblockResult['success'], isTrue);
      expect(unblockResult['is_flagged'], isFalse);
    });
  });
}
