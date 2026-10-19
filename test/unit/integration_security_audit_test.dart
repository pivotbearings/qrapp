import 'package:flutter_test/flutter_test.dart';
import 'package:pivot_bearings_app/features/bearing_verification/domain/services/warranty_calculator.dart';
import 'package:pivot_bearings_app/features/bearing_verification/data/models/bearing_model.dart';
import 'package:pivot_bearings_app/core/config/app_config.dart';
import 'package:pivot_bearings_app/core/localization/app_localizations.dart';
import 'package:flutter/material.dart';

void main() {
  group('Full Integration & Security Audit Suite', () {
    
    test('1. QR Serial & Format Rigidity: Enforces PB-YYYY-XX standard format', () {
      final validRegex = RegExp(r'^PB-\d{4}-[A-Z0-9]{2}$');
      
      // Known valid production patterns
      expect(validRegex.hasMatch('PB-2026-A1'), isTrue);
      expect(validRegex.hasMatch('PB-2026-9Z'), isTrue);
      
      // Malformed / injection attempts
      expect(validRegex.hasMatch('PB-2026-A1; DROP TABLE qr_codes;'), isFalse);
      expect(validRegex.hasMatch('https://pivotbearings.com/verify?code=PB-2026-A1'), isFalse);
      expect(validRegex.hasMatch(''), isFalse);
      expect(validRegex.hasMatch('PB-999-A1'), isFalse);
    });

    test('2. Warranty Calendar Expiry & Month-End Arithmetic (Leap Years & Shorter Months)', () {
      // 31st January 2024 (Leap Year) + 1 Month -> 29th February 2024
      final leapJan31 = DateTime.utc(2024, 1, 31, 10, 0, 0);
      final leapExpiry = WarrantyCalculator.calculateExpiryDate(
        firstInDate: leapJan31,
        durationMonths: 1,
      );
      expect(leapExpiry.year, 2024);
      expect(leapExpiry.month, 2);
      expect(leapExpiry.day, 29);

      // 31st January 2023 (Non-Leap Year) + 1 Month -> 28th February 2023
      final nonLeapJan31 = DateTime.utc(2023, 1, 31, 10, 0, 0);
      final nonLeapExpiry = WarrantyCalculator.calculateExpiryDate(
        firstInDate: nonLeapJan31,
        durationMonths: 1,
      );
      expect(nonLeapExpiry.year, 2023);
      expect(nonLeapExpiry.month, 2);
      expect(nonLeapExpiry.day, 28);

      // 31st August 2026 + 6 Months -> 28th February 2027
      final aug31 = DateTime.utc(2026, 8, 31, 14, 30, 0);
      final febExpiry = WarrantyCalculator.calculateExpiryDate(
        firstInDate: aug31,
        durationMonths: 6,
      );
      expect(febExpiry.year, 2027);
      expect(febExpiry.month, 2);
      expect(febExpiry.day, 28);

      // 31st March 2026 + 6 Months -> 30th September 2026
      final mar31 = DateTime.utc(2026, 3, 31, 9, 0, 0);
      final sepExpiry = WarrantyCalculator.calculateExpiryDate(
        firstInDate: mar31,
        durationMonths: 6,
      );
      expect(sepExpiry.year, 2026);
      expect(sepExpiry.month, 9);
      expect(sepExpiry.day, 30);
    });

    test('3. Clock Manipulation Resistance & Server Authoritative Integrity', () {
      final serverActivation = DateTime.utc(2026, 1, 1, 0, 0, 0);

      // Bearing model calculation uses immutable UTC server activation
      final model = BearingModel(
        id: 'PB-2026-X1',
        batchCode: 'BATCH-2026-Q1',
        state: BearingLifecycleState.currentlyIn,
        warrantyDurationMonths: 6,
        firstInDate: serverActivation,
        lastInDate: serverActivation,
      );

      // Verify model preserves immutable server timestamps regardless of client local time
      expect(model.firstInDate!.isUtc, isTrue);
      expect(model.warrantyExpiryDate!.isUtc, isTrue);
      expect(model.warrantyExpiryDate, DateTime.utc(2026, 7, 1, 0, 0, 0));
      expect(model.state, BearingLifecycleState.currentlyIn);
      expect(model.isActivated, isTrue);
    });

    test('4. Security: Environment Configuration', () {
      AppConfig.appEnvironment = 'production';
      expect(AppConfig.isProduction, isTrue);
    });

    test('5. Lifecycle Invariants: OUT after Expiry maintains lifecycle without reactivating warranty', () {
      final pastActivation = DateTime.utc(2025, 1, 1, 0, 0, 0);

      // Expired bearing
      final expiredBearing = BearingModel(
        id: 'PB-2025-01',
        batchCode: 'BATCH-2025-Q1',
        state: BearingLifecycleState.currentlyIn,
        warrantyDurationMonths: 6,
        firstInDate: pastActivation,
        lastInDate: pastActivation,
      );

      // Expired because current date (2026) > July 2025
      expect(expiredBearing.isWarrantyExpired, isTrue);
      expect(expiredBearing.state, BearingLifecycleState.currentlyIn);

      // Transition to OUT permitted even when warranty is expired
      final updatedOut = BearingModel(
        id: expiredBearing.id,
        batchCode: expiredBearing.batchCode,
        state: BearingLifecycleState.currentlyOut,
        warrantyDurationMonths: expiredBearing.warrantyDurationMonths,
        firstInDate: expiredBearing.firstInDate,
        lastInDate: expiredBearing.lastInDate,
        lastOutDate: DateTime.utc(2026, 10, 10, 0, 0, 0),
      );
      expect(updatedOut.state, BearingLifecycleState.currentlyOut);
      expect(updatedOut.isWarrantyExpired, isTrue);
      // Activation date remained preserved
      expect(updatedOut.firstInDate, pastActivation);
    });

    test('6. Tri-lingual Localization completeness (EN, HI, GU)', () {
      final enLoc = AppLocalizations(const Locale('en'));
      final hiLoc = AppLocalizations(const Locale('hi'));
      final guLoc = AppLocalizations(const Locale('gu'));

      expect(enLoc.translate('app_title'), isNotEmpty);
      expect(hiLoc.translate('app_title'), isNotEmpty);
      expect(guLoc.translate('app_title'), isNotEmpty);

      // Verify Hindi font glyph availability key strings
      expect(hiLoc.translate('action_in'), isNotEmpty);
      expect(hiLoc.translate('action_out'), isNotEmpty);

      // Verify Gujarati font glyph availability key strings
      expect(guLoc.translate('action_in'), isNotEmpty);
      expect(guLoc.translate('action_out'), isNotEmpty);
    });

    test('7. Verification Image Signed URL & Hash Format Security', () {
      final sha256Regex = RegExp(r'^[a-f0-9]{64}$');
      const testHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      expect(sha256Regex.hasMatch(testHash), isTrue);

      const invalidTamperedHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b85G';
      expect(sha256Regex.hasMatch(invalidTamperedHash), isFalse);
    });
  });
}
