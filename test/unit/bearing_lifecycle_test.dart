import 'package:flutter_test/flutter_test.dart';
import 'package:pivot_bearings_app/features/bearing_verification/data/models/bearing_model.dart';
import 'package:pivot_bearings_app/features/bearing_verification/data/repositories/bearing_repository.dart';
import 'package:pivot_bearings_app/features/bearing_verification/domain/models/qr_verification_result.dart';
import 'package:pivot_bearings_app/features/bearing_verification/domain/services/warranty_calculator.dart';

void main() {
  group('Authoritative Bearing Lifecycle State Machine Tests', () {
    late BearingRepository repository;

    setUp(() {
      repository = BearingRepositoryImpl();

      // Register clean dynamic test bearings
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

    test('1. First IN: Activates Warranty & Sets Lifecycle to CURRENTLY_IN', () async {
      // PB-9402-XJ starts in notActivated state
      final initial = await repository.getBearingById('PB-9402-XJ');
      expect(initial?.state, BearingLifecycleState.notActivated);
      expect(initial?.firstInDate, isNull);

      final markedIn = await repository.markBearingIn('PB-9402-XJ');
      expect(markedIn.state, BearingLifecycleState.currentlyIn);
      expect(markedIn.firstInDate, isNotNull);
      expect(markedIn.lastInDate, isNotNull);
      expect(markedIn.firstInDate, markedIn.lastInDate);

      // Verify warranty horizon calculation
      final expectedExpiry = WarrantyCalculator.calculateExpiryDate(
        firstInDate: markedIn.firstInDate!,
        durationMonths: markedIn.warrantyDurationMonths,
      );
      expect(markedIn.warrantyExpiryDate, expectedExpiry);
    });

    test('2. Confirmed OUT: Records Removal & Transitions to CURRENTLY_OUT', () async {
      // PB-7701-AB is currently IN
      final initial = await repository.getBearingById('PB-7701-AB');
      expect(initial?.state, BearingLifecycleState.currentlyIn);

      final markedOut = await repository.markBearingOut('PB-7701-AB');
      expect(markedOut.state, BearingLifecycleState.currentlyOut);
      expect(markedOut.lastOutDate, isNotNull);
      expect(markedOut.firstInDate, initial?.firstInDate, reason: 'First IN date must remain strictly preserved');
    });

    test('3. Re-installation Strictly Prohibited: Once marked OUT, subsequent IN is blocked', () async {
      // Start with notActivated
      final firstIn = await repository.markBearingIn('PB-9402-XJ');
      expect(firstIn.state, BearingLifecycleState.currentlyIn);

      // Operator scans again and marks OUT with removal proof
      final out = await repository.markBearingOut('PB-9402-XJ');
      expect(out.state, BearingLifecycleState.currentlyOut);

      // STRICT TERMINAL LIFECYCLE: Re-installation must be rejected
      expect(
        () => repository.markBearingIn('PB-9402-XJ'),
        throwsA(isA<StateError>()),
      );
    });

    test('4. Verification Payload for CURRENTLY_OUT Bearing Returns Terminal Decommissioned Status', () async {
      // PB-8812-KR is already marked OUT
      final result = await repository.verifyScannedPayload('PB-8812-KR');
      expect(result.status, QrVerificationStatus.decommissionedOut);
      expect(result.canMarkIn, isFalse, reason: 'Must not allow re-installation');
      expect(result.canMarkOut, isFalse, reason: 'Already marked out');
      expect(result.currentLifecycleState, 'CURRENTLY_OUT');
      expect(result.errorMessage, contains('decommissioned'));
    });

    test('5. Month-End & Leap Year Calendar Arithmetic Invariants', () {
      // Leap year Feb 29 + 12 months = Feb 28 of subsequent non-leap year
      final leapFeb29 = DateTime(2024, 2, 29);
      final expiry12M = WarrantyCalculator.calculateExpiryDate(
        firstInDate: leapFeb29,
        durationMonths: 12,
      );
      expect(expiry12M.year, 2025);
      expect(expiry12M.month, 2);
      expect(expiry12M.day, 28);

      // Jan 31 + 1 month in a leap year (2024) = Feb 29
      final jan31Leap = DateTime(2024, 1, 31);
      final expiry1MLeap = WarrantyCalculator.calculateExpiryDate(
        firstInDate: jan31Leap,
        durationMonths: 1,
      );
      expect(expiry1MLeap.year, 2024);
      expect(expiry1MLeap.month, 2);
      expect(expiry1MLeap.day, 29);

      // Jan 31 + 1 month in a non-leap year (2025) = Feb 28
      final jan31NonLeap = DateTime(2025, 1, 31);
      final expiry1MNonLeap = WarrantyCalculator.calculateExpiryDate(
        firstInDate: jan31NonLeap,
        durationMonths: 1,
      );
      expect(expiry1MNonLeap.year, 2025);
      expect(expiry1MNonLeap.month, 2);
      expect(expiry1MNonLeap.day, 28);
    });

    test('6. OUT Remains Fully Allowed After Warranty Expiry', () async {
      // PB-8812-KR was marked OUT after expiration
      final bearing = await repository.getBearingById('PB-8812-KR');
      expect(bearing?.state, BearingLifecycleState.currentlyOut);
      expect(bearing?.lastOutDate, isNotNull);
    });
  });
}
