import 'package:flutter_test/flutter_test.dart';
import 'package:pivot_bearings_app/features/bearing_verification/domain/services/warranty_calculator.dart';

void main() {
  group('WarrantyCalculator Unit Tests', () {
    test('Calculates 6-month expiry date accurately', () {
      final inDate = DateTime(2026, 10, 24, 10, 30);
      final expiry = WarrantyCalculator.calculateExpiryDate(
        firstInDate: inDate,
        durationMonths: 6,
      );

      expect(expiry.year, equals(2027));
      expect(expiry.month, equals(4));
      expect(expiry.day, equals(24));
    });

    test('Calculates 12-month expiry date accurately', () {
      final inDate = DateTime(2026, 1, 15);
      final expiry = WarrantyCalculator.calculateExpiryDate(
        firstInDate: inDate,
        durationMonths: 12,
      );

      expect(expiry.year, equals(2027));
      expect(expiry.month, equals(1));
      expect(expiry.day, equals(15));
    });

    test('Reports warranty as active when current time is before expiry', () {
      final inDate = DateTime(2026, 10, 1);
      final checkDate = DateTime(2026, 12, 1);

      final isActive = WarrantyCalculator.isWarrantyActive(
        firstInDate: inDate,
        durationMonths: 6,
        currentTime: checkDate,
      );

      expect(isActive, isTrue);
    });

    test('Reports warranty as inactive when current time is after expiry', () {
      final inDate = DateTime(2026, 1, 1);
      final checkDate = DateTime(2026, 8, 1);

      final isActive = WarrantyCalculator.isWarrantyActive(
        firstInDate: inDate,
        durationMonths: 6,
        currentTime: checkDate,
      );

      expect(isActive, isFalse);
    });

    test('Calculates and formats operating cycle duration correctly', () {
      final inDate = DateTime(2026, 10, 8, 10, 42);
      final outDate = inDate.add(const Duration(days: 73, hours: 4, minutes: 48));

      final duration = WarrantyCalculator.calculateOperatingDuration(
        inTimestamp: inDate,
        outTimestamp: outDate,
      );

      final formatted = WarrantyCalculator.formatOperatingDuration(duration);
      expect(formatted, equals('73 Days, 04 Hours, 48 Mins'));
    });
  });
}
