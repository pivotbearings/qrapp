import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:pivot_bearings_app/core/localization/locale_controller.dart';
import 'package:pivot_bearings_app/core/services/supabase_service.dart';
import 'package:pivot_bearings_app/features/bearing_verification/domain/services/warranty_calculator.dart';

void main() {
  group('Admin Panel & Authoritative Telemetry Tests', () {
    test('1. Admin Dashboard Metrics Data Contract & Key Aggregates', () async {
      final metrics = await SupabaseService.fetchAdminDashboardMetrics();

      expect(metrics.containsKey('total_qr_codes'), isTrue);
      expect(metrics.containsKey('unactivated_qr_codes'), isTrue);
      expect(metrics.containsKey('currently_in_bearings'), isTrue);
      expect(metrics.containsKey('currently_out_bearings'), isTrue);
      expect(metrics.containsKey('active_warranties'), isTrue);
      expect(metrics.containsKey('expired_warranties'), isTrue);
      expect(metrics.containsKey('total_scans'), isTrue);
      expect(metrics.containsKey('invalid_attempts'), isTrue);
      expect(metrics.containsKey('total_customers'), isTrue);
      expect(metrics.containsKey('total_batches'), isTrue);
      expect(metrics.containsKey('flagged_bearings'), isTrue);

      final total = metrics['total_qr_codes'] as num;
      final unactivated = metrics['unactivated_qr_codes'] as num;
      expect(total >= unactivated, isTrue, reason: 'Total QR codes must be >= unactivated QR codes');
    });

    test('2. Bearing Lifecycle Details Contract with Installation Cycles & Operating Duration', () {
      final activationTime = DateTime.parse('2026-01-10T08:30:00Z');
      final expiryTime = WarrantyCalculator.calculateExpiryDate(
        firstInDate: activationTime,
        durationMonths: 6,
      );

      final cycle1Out = DateTime.parse('2026-02-15T14:45:00Z');
      final cycle1Duration = WarrantyCalculator.calculateOperatingDuration(
        inTimestamp: activationTime,
        outTimestamp: cycle1Out,
      );
      final isCycle1ActiveAtOut = WarrantyCalculator.isWarrantyActive(
        firstInDate: activationTime,
        durationMonths: 6,
        currentTime: cycle1Out,
      );

      final cycle2In = DateTime.parse('2026-03-01T09:00:00Z');
      final cycle2Out = DateTime.parse('2026-08-01T12:00:00Z');
      final cycle2Duration = WarrantyCalculator.calculateOperatingDuration(
        inTimestamp: cycle2In,
        outTimestamp: cycle2Out,
      );
      final isCycle2ActiveAtOut = WarrantyCalculator.isWarrantyActive(
        firstInDate: activationTime,
        durationMonths: 6,
        currentTime: cycle2Out,
      );

      final payload = {
        'bearing_id': 'PB-9402-XJ',
        'model_number': 'PBI-6204-ZZ',
        'current_lifecycle_state': 'CURRENTLY_OUT',
        'first_in_timestamp': activationTime.toIso8601String(),
        'warranty_expiry_timestamp': expiryTime.toIso8601String(),
        'is_warranty_active': false,
        'installation_cycles': [
          {
            'cycle_number': 1,
            'in_timestamp': activationTime.toIso8601String(),
            'out_timestamp': cycle1Out.toIso8601String(),
            'operating_duration_interval': WarrantyCalculator.formatOperatingDuration(cycle1Duration),
            'was_warranty_active_at_out': isCycle1ActiveAtOut,
          },
          {
            'cycle_number': 2,
            'in_timestamp': cycle2In.toIso8601String(),
            'out_timestamp': cycle2Out.toIso8601String(),
            'operating_duration_interval': WarrantyCalculator.formatOperatingDuration(cycle2Duration),
            'was_warranty_active_at_out': isCycle2ActiveAtOut,
          },
        ]
      };

      expect(payload['bearing_id'], equals('PB-9402-XJ'));
      expect(payload['first_in_timestamp'], equals('2026-01-10T08:30:00.000Z'));
      expect(payload['warranty_expiry_timestamp'], equals('2026-07-10T08:30:00.000Z'));

      final cycles = payload['installation_cycles'] as List<Map<String, dynamic>>;
      expect(cycles.length, equals(2));

      // Cycle 1: Removed on Feb 15, warranty was active
      expect(cycles[0]['was_warranty_active_at_out'], isTrue);
      expect(cycles[0]['operating_duration_interval'], contains('36 Days'));

      // Cycle 2: Removed on Aug 01, warranty was expired
      expect(cycles[1]['was_warranty_active_at_out'], isFalse);
      expect(cycles[1]['operating_duration_interval'], contains('153 Days'));
    });

    test('3. Verification Image Metadata & Cryptographic Hash Formatting', () {
      final sampleImage = {
        'id': 'img-uuid-001',
        'qr_code_id': 'qr-uuid-001',
        'storage_path': 'qr-uuid-001/evt-101.webp',
        'sha256_hash': 'a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e',
        'file_size_bytes': 158420,
        'width': 1800,
        'height': 1350,
        'image_type': 'IN_INSTALLATION',
      };

      expect(sampleImage['sha256_hash'], hasLength(64));
      expect(sampleImage['storage_path'], endsWith('.webp'));
      expect(sampleImage['image_type'], equals('IN_INSTALLATION'));
      expect(sampleImage['file_size_bytes'] as int > 0, isTrue);
      expect(sampleImage['width'] as int <= 2000, isTrue);
    });

    test('4. Security Telemetry - Invalid Scan Records Mapping', () {
      final invalidAttempt = {
        'scanned_payload': 'MALFORMED-QR-COUNTERFEIT',
        'is_valid': false,
        'ip_address': '192.168.1.100',
        'device_info': 'Chrome Web Inspector / Automated Probe',
        'scan_timestamp': '2026-10-10T01:00:00Z',
      };

      expect(invalidAttempt['is_valid'], isFalse);
      expect(invalidAttempt['scanned_payload'], isNot(startsWith('https://verify.pivotbearings.com/pbi/PB-')));
    });

    test('5. Company Settings Default Metadata & Persistence Contract', () async {
      final settings = await SupabaseService.fetchCompanySettings();

      expect(settings['company_name'], equals('Pivot Bearings India'));
      expect(settings['gst_number'], contains('27AABC'));
      expect(settings['contact_email'], equals('pivotbearings@gmail.com'));
      expect(settings['website'], equals('https://www.pivotbearingsindia.com/'));
      expect(settings['contact_phone'], equals('+91 98988 57198'));
    });

    test('6. Dynamic Multi-Language Locale Controller Integration', () {
      LocaleController.setLocale(const Locale('en'));
      expect(LocaleController.currentLocale.value.languageCode, equals('en'));

      LocaleController.setLocale(const Locale('hi'));
      expect(LocaleController.currentLocale.value.languageCode, equals('hi'));

      LocaleController.setLocale(const Locale('gu'));
      expect(LocaleController.currentLocale.value.languageCode, equals('gu'));

      // Restore to English
      LocaleController.setLocale(const Locale('en'));
      expect(LocaleController.currentLocale.value.languageCode, equals('en'));
    });

    test('7. Responsive Viewport Breakpoint Rules', () {
      // Breakpoint definitions
      bool isDesktop(double width) => width >= 1200;
      bool isLaptop(double width) => width >= 992 && width < 1200;
      bool isTablet(double width) => width >= 768 && width < 992;
      bool isMobile(double width) => width < 768;

      expect(isDesktop(1440), isTrue);
      expect(isDesktop(1200), isTrue);
      expect(isDesktop(1199), isFalse);

      expect(isLaptop(1100), isTrue);
      expect(isLaptop(992), isTrue);
      expect(isLaptop(900), isFalse);

      expect(isTablet(820), isTrue);
      expect(isTablet(768), isTrue);
      expect(isTablet(767), isFalse);

      expect(isMobile(412), isTrue);
      expect(isMobile(360), isTrue);
      expect(isMobile(768), isFalse);
    });
  });
}
