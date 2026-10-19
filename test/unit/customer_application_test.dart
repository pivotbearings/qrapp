import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pivot_bearings_app/core/constants/app_typography.dart';
import 'package:pivot_bearings_app/core/localization/app_localizations.dart';
import 'package:pivot_bearings_app/core/localization/locale_controller.dart';
import 'package:pivot_bearings_app/core/services/supabase_service.dart';
import 'package:pivot_bearings_app/features/bearing_verification/data/models/bearing_model.dart';
import 'package:pivot_bearings_app/features/bearing_verification/domain/services/warranty_calculator.dart';

void main() {
  group('Customer-Facing Application & Localization Tests', () {
    test('1. Multi-Language Localization - Completeness across EN, HI, GU', () {
      final locEn = AppLocalizations(const Locale('en'));
      final locHi = AppLocalizations(const Locale('hi'));
      final locGu = AppLocalizations(const Locale('gu'));

      const testKeys = [
        'app_title',
        'home',
        'scan_bearing_qr',
        'bearing_verified',
        'warranty_active',
        'warranty_expired',
        'invalid_qr_code',
        'currently_in',
        'currently_out',
        'installation_duration',
        'first_in_date',
        'expiry_date',
        'lifecycle_history',
        'customer_profile',
        'language_settings',
        'gst_number',
      ];

      for (final key in testKeys) {
        final enVal = locEn.translate(key);
        final hiVal = locHi.translate(key);
        final guVal = locGu.translate(key);

        expect(enVal, isNotEmpty, reason: 'Key $key must exist in English');
        expect(hiVal, isNotEmpty, reason: 'Key $key must exist in Hindi');
        expect(guVal, isNotEmpty, reason: 'Key $key must exist in Gujarati');

        // Hindi and Gujarati must have translated text, not fall back to English key
        expect(hiVal, isNot(equals(key)), reason: 'Key $key must be translated in Hindi');
        expect(guVal, isNot(equals(key)), reason: 'Key $key must be translated in Gujarati');
      }
    });

    test('2. Dynamic Locale Switching with LocaleController', () {
      expect(LocaleController.locale.languageCode, equals('en'));

      LocaleController.setLanguageCode('hi');
      expect(LocaleController.locale.languageCode, equals('hi'));

      LocaleController.setLanguageCode('gu');
      expect(LocaleController.locale.languageCode, equals('gu'));

      LocaleController.setLanguageCode('en');
      expect(LocaleController.locale.languageCode, equals('en'));
    });

    test('3. Font Configuration - NeueHaas Light and Roman', () {
      expect(AppTypography.fontFamily, equals('NeueHaas'));
      expect(AppTypography.fontFamilyFallback, isEmpty);
      expect(AppTypography.headlineLg.fontFamily, equals('NeueHaas'));
      expect(AppTypography.headlineLg.fontFamilyFallback, isNull);
    });

    test('4. Understandable States Display Formats', () {
      final bearingIn = BearingModel(
        id: 'PB-9402-XJ',
        batchCode: 'BATCH-2026-OCT-A',
        state: BearingLifecycleState.currentlyIn,
        warrantyDurationMonths: 6,
        firstInDate: DateTime.now().subtract(const Duration(days: 30)),
      );
      expect(bearingIn.stateDisplayString, equals('[STATUS: MARKED IN]'));
      expect(bearingIn.isActivated, isTrue);
      expect(bearingIn.isWarrantyExpired, isFalse);

      final bearingOut = BearingModel(
        id: 'PB-8812-KR',
        batchCode: 'BATCH-2026-OCT-A',
        state: BearingLifecycleState.currentlyOut,
        warrantyDurationMonths: 12,
        firstInDate: DateTime.now().subtract(const Duration(days: 400)),
        lastOutDate: DateTime.now().subtract(const Duration(days: 10)),
      );
      expect(bearingOut.stateDisplayString, equals('[STATUS: MARKED OUT]'));
      expect(bearingOut.isWarrantyExpired, isTrue);
    });

    test('5. Operating Duration Computation & String Formatting', () {
      final inTime = DateTime(2026, 1, 1, 10, 0);
      final outTime = inTime.add(const Duration(days: 45, hours: 6, minutes: 30));

      final duration = WarrantyCalculator.calculateOperatingDuration(
        inTimestamp: inTime,
        outTimestamp: outTime,
      );

      final formatted = WarrantyCalculator.formatOperatingDuration(duration);
      expect(formatted, equals('45 Days, 06 Hours, 30 Mins'));
    });

    test('6. Company Information Defaults from SupabaseService', () async {
      final company = await SupabaseService.fetchCompanySettings();
      expect(company['company_name'], contains('Pivot Bearings'));
      expect(company['gst_number'], isNotEmpty);
      expect(company['contact_email'], isNotEmpty);
      expect(company['contact_phone'], isNotEmpty);
    });

    test('7. Customer Profile Defaults from SupabaseService', () async {
      final profile = await SupabaseService.fetchUserProfile();
      expect(profile['company_name'], isNotEmpty);
      expect(profile['facility_code'], isNotEmpty);
      expect(profile['role'], isIn(['USER', 'ADMIN']));
    });
  });
}
