import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pivot_bearings_app/features/qr_generation/data/repositories/qr_management_repository.dart';
import 'package:pivot_bearings_app/features/bearing_verification/data/repositories/bearing_repository.dart';
import 'package:pivot_bearings_app/features/bearing_verification/data/models/bearing_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    QrManagementRepository.clearInMemoryCache();
  });

  test('QR Registry persists generated batches and QR codes across reloads', () async {
    final repo = QrManagementRepository();

    // 1. Generate 10 QRs
    final result = await repo.generateQrBatch(
      batchCode: 'BATCH-PERSIST-001',
      plantLocation: 'Plant 02 — Chakan',
      quantity: 10,
      modelNumber: 'PBI-6204-ZZ',
    );

    expect(result['success'], isTrue);
    final ids = (result['bearing_ids'] as List).map((e) => e.toString()).toList();
    expect(ids.length, 10);

    // Verify in-memory before reload
    final beforeReload = await repo.fetchQrCodes();
    expect(beforeReload.any((q) => ids.contains(q['bearing_id'])), isTrue);

    // 2. Simulate complete browser refresh / page reload:
    // Memory wiped completely
    QrManagementRepository.clearInMemoryCache();
    expect(QrManagementRepository.inMemoryQrCodes.isEmpty, isTrue);

    // Reload from local storage
    await QrManagementRepository.loadFromLocalStorage();

    final afterReload = await repo.fetchQrCodes();
    expect(afterReload.length, equals(10));
    for (final id in ids) {
      expect(afterReload.any((q) => q['bearing_id'] == id), isTrue,
          reason: 'Generated bearing $id must persist in local storage across refresh');
    }

    // 3. Verify batches persist
    final batches = await repo.fetchBatches();
    expect(batches.any((b) => b['batch_code'] == 'BATCH-PERSIST-001'), isTrue);

    // 4. Verify bearing repository recognizes the persisted bearings
    final bearingRepo = BearingRepositoryImpl();
    final firstBearing = await bearingRepo.getBearingById(ids.first);
    expect(firstBearing, isNotNull);
    expect(firstBearing!.id, equals(ids.first));

    // 5. Test state lifecycle synchronization: Mark IN, simulate reload, verify CURRENTLY_IN persists
    await bearingRepo.markBearingIn(ids.first);
    QrManagementRepository.clearInMemoryCache();
    await QrManagementRepository.loadFromLocalStorage();

    final reloadedBearing = await bearingRepo.getBearingById(ids.first);
    expect(reloadedBearing!.state, equals(BearingLifecycleState.currentlyIn));

    final qrListAfterIn = await repo.fetchQrCodes();
    final updatedQr = qrListAfterIn.firstWhere((q) => q['bearing_id'] == ids.first);
    expect(updatedQr['current_lifecycle_state'], equals('CURRENTLY_IN'));
  });
}
