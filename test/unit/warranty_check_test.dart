import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pivot_bearings_app/features/bearing_verification/data/models/bearing_model.dart';
import 'package:pivot_bearings_app/features/warranty_check/presentation/screens/warranty_check_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Warranty Check & Category Resolution Tests', () {
    test('1. Resolves accurate bearing categories across diverse bearing families', () {
      const ballBearing = BearingModel(
        id: 'PB-6204-01',
        batchCode: 'BATCH-2026-A',
        modelNumber: 'PBI-6204-ZZ',
      );
      expect(ballBearing.category, equals('Deep Groove Ball Bearing'));

      const sphericalBearing = BearingModel(
        id: 'PB-22216-01',
        batchCode: 'BATCH-2026-B',
        modelNumber: 'PBI-22216-E',
      );
      expect(sphericalBearing.category, equals('Spherical Roller Bearing'));

      const taperedBearing = BearingModel(
        id: 'PB-30206-01',
        batchCode: 'BATCH-2026-C',
        modelNumber: 'PBI-30206-CR',
      );
      expect(taperedBearing.category, equals('Tapered Roller Bearing'));

      const cylindricalBearing = BearingModel(
        id: 'PB-NU208-01',
        batchCode: 'BATCH-2026-D',
        modelNumber: 'PBI-NU208-ECP',
      );
      expect(cylindricalBearing.category, equals('Cylindrical Roller Bearing'));
    });

    test('2. Correctly computes days left to expire warranty and displays clear badges', () {
      final now = DateTime.now();

      // Bearing with 100 days remaining
      final activeBearing = BearingModel(
        id: 'PB-ACTIVE-01',
        batchCode: 'BATCH-2026-A',
        state: BearingLifecycleState.currentlyIn,
        firstInDate: now.subtract(const Duration(days: 80)),
        explicitExpiryDate: now.add(const Duration(days: 100)),
      );
      expect(activeBearing.isUnderWarranty, isTrue);
      expect(activeBearing.isWarrantyExpired, isFalse);
      expect(activeBearing.daysLeftToExpiry, equals(100));
      expect(activeBearing.warrantyDaysLeftDisplay, equals('100 Days Left'));

      // Bearing expired 15 days ago
      final expiredBearing = BearingModel(
        id: 'PB-EXPIRED-01',
        batchCode: 'BATCH-2026-A',
        state: BearingLifecycleState.currentlyIn,
        firstInDate: now.subtract(const Duration(days: 200)),
        explicitExpiryDate: now.subtract(const Duration(days: 15)),
      );
      expect(expiredBearing.isUnderWarranty, isFalse);
      expect(expiredBearing.isWarrantyExpired, isTrue);
      expect(expiredBearing.daysLeftToExpiry, equals(-15));
      expect(expiredBearing.warrantyDaysLeftDisplay, equals('Expired 15 Days Ago'));

      // Unactivated bearing
      const pendingBearing = BearingModel(
        id: 'PB-PENDING-01',
        batchCode: 'BATCH-2026-A',
        warrantyDurationMonths: 6,
        state: BearingLifecycleState.notActivated,
      );
      expect(pendingBearing.isUnderWarranty, isTrue);
      expect(pendingBearing.isWarrantyExpired, isFalse);
      expect(pendingBearing.daysLeftToExpiry, isNull);
      expect(pendingBearing.warrantyDaysLeftDisplay, contains('Pending Activation'));
    });

    testWidgets('3. Renders WarrantyCheckScreen with scan button and input controls', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: WarrantyCheckScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('WARRANTY CHECK'), findsWidgets);
      expect(find.text('SCAN QR TO CHECK WARRANTY'), findsOneWidget);
      expect(find.text('CHECK'), findsOneWidget);
      expect(find.text('MY QR CODES UNDER WARRANTY'), findsOneWidget);
    });
  });
}
