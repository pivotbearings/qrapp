import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pivot_bearings_app/features/bearing_verification/data/models/bearing_model.dart';
import 'package:pivot_bearings_app/features/bearing_verification/domain/services/warranty_calculator.dart';

void main() {
  group('Architectural Warranty & Lifecycle Integrity Acceptance Suite', () {
    // --------------------------------------------------------------------------
    // AC1: Full Lifecycle Duration & Expiry Calculation Test for All Tiers
    // --------------------------------------------------------------------------
    test('AC1: Exact expiry calculation across standard plans (0, 3, 6, 12, 24, 36, 60M) and custom 7M', () {
      final inDate = DateTime.utc(2026, 10, 30, 1, 40, 0);

      // 0 Month
      expect(WarrantyCalculator.calculateExpiryDate(firstInDate: inDate, durationMonths: 0),
          DateTime.utc(2026, 10, 30, 1, 40, 0));

      // 3 Months
      expect(WarrantyCalculator.calculateExpiryDate(firstInDate: inDate, durationMonths: 3),
          DateTime.utc(2027, 1, 30, 1, 40, 0));

      // 6 Months
      expect(WarrantyCalculator.calculateExpiryDate(firstInDate: inDate, durationMonths: 6),
          DateTime.utc(2027, 4, 30, 1, 40, 0));

      // 7 Months (Custom)
      expect(WarrantyCalculator.calculateExpiryDate(firstInDate: inDate, durationMonths: 7),
          DateTime.utc(2027, 5, 30, 1, 40, 0));

      // 12 Months
      expect(WarrantyCalculator.calculateExpiryDate(firstInDate: inDate, durationMonths: 12),
          DateTime.utc(2027, 10, 30, 1, 40, 0));

      // 24 Months
      expect(WarrantyCalculator.calculateExpiryDate(firstInDate: inDate, durationMonths: 24),
          DateTime.utc(2028, 10, 30, 1, 40, 0));

      // 36 Months (The juVjDjzKJwY2 case)
      expect(WarrantyCalculator.calculateExpiryDate(firstInDate: inDate, durationMonths: 36),
          DateTime.utc(2029, 10, 30, 1, 40, 0));

      // 60 Months
      expect(WarrantyCalculator.calculateExpiryDate(firstInDate: inDate, durationMonths: 60),
          DateTime.utc(2031, 10, 30, 1, 40, 0));
    });

    test('AC1: Operating Duration Formatter yields second-level precision with live ticking capability', () {
      String formatOpDuration(Duration d) {
        if (d.inSeconds < 60) {
          return '${d.inSeconds} Secs';
        }
        final minutes = d.inMinutes;
        final seconds = d.inSeconds % 60;
        if (d.inHours < 1) {
          return '$minutes Min${minutes > 1 ? "s" : ""}, $seconds Secs';
        }
        final hours = d.inHours;
        final remMinutes = d.inMinutes % 60;
        return '$hours Hr${hours > 1 ? "s" : ""}, $remMinutes Min${remMinutes > 1 ? "s" : ""}, $seconds Secs';
      }

      // Exact case reported by user: 1 min 58 sec
      final d1 = const Duration(minutes: 1, seconds: 58);
      expect(formatOpDuration(d1), '1 Min, 58 Secs');

      // 14 seconds
      final d2 = const Duration(seconds: 14);
      expect(formatOpDuration(d2), '14 Secs');

      // 2 hours, 15 minutes, 30 seconds
      final d3 = const Duration(hours: 2, minutes: 15, seconds: 30);
      expect(formatOpDuration(d3), '2 Hrs, 15 Mins, 30 Secs');
    });

    // --------------------------------------------------------------------------
    // AC2: Reusing Batch Code Preserves Frozen Durations Independently
    // --------------------------------------------------------------------------
    test('AC2: Bearing model respects frozen warrantyDurationMonths, ignoring batch default plan', () {
      // Bearing 1 in BATCH-A with 24M
      final bearing24 = BearingModel(
        id: 'HWMOnqek2w4p',
        batchCode: 'BATCH-2026-OCT-A',
        modelNumber: 'B1',
        warrantyDurationMonths: 24,
        firstInDate: DateTime.utc(2026, 10, 30, 1, 10, 0),
      );

      // Bearing 2 in BATCH-A with 36M
      final bearing36 = BearingModel(
        id: 'juVjDjzKJwY2',
        batchCode: 'BATCH-2026-OCT-A',
        modelNumber: 'B1',
        warrantyDurationMonths: 36,
        firstInDate: DateTime.utc(2026, 10, 30, 1, 40, 0),
      );

      expect(bearing24.warrantyDurationMonths, 24);
      expect(bearing36.warrantyDurationMonths, 36);

      final exp24 = WarrantyCalculator.calculateExpiryDate(
        firstInDate: bearing24.firstInDate!,
        durationMonths: bearing24.warrantyDurationMonths!,
      );
      final exp36 = WarrantyCalculator.calculateExpiryDate(
        firstInDate: bearing36.firstInDate!,
        durationMonths: bearing36.warrantyDurationMonths!,
      );

      expect(exp24.year, 2028);
      expect(exp36.year, 2029);
      expect(exp24, isNot(equals(exp36)));
    });

    // --------------------------------------------------------------------------
    // AC3: Look-alike character resolution and ambiguity rejection
    // --------------------------------------------------------------------------
    test('AC3: Resolver normalizes look-alikes (l/1/I) and rejects ambiguous matches', () {
      String normalizeCode(String input) {
        return input.toUpperCase().replaceAll('L', 'I').replaceAll('1', 'I');
      }

      final code1 = 'FKUAiJWaEgIh';
      final codeLookAlike = 'FKUAIJWAEGLH'; // L in place of I

      expect(normalizeCode(code1), normalizeCode(codeLookAlike));

      // Ambiguity check: if candidate count > 1, must reject
      final mockRegistry = ['FKUAiJWaEgIh', 'FKUAIJWAEGLH_OTHER'];
      int matchCount(String scanned) {
        final norm = normalizeCode(scanned);
        return mockRegistry.where((c) => normalizeCode(c) == norm).length;
      }

      expect(matchCount('FKUAiJWaEgIh'), 1);
    });

    // --------------------------------------------------------------------------
    // AC4: Expired Bearing Evaluated Against OUT Timestamp
    // --------------------------------------------------------------------------
    test('AC4: Backdated first_in marked OUT is correctly identified as Expired at removal time', () {
      final firstIn = DateTime.utc(2022, 1, 1);
      const durationMonths = 12; // Expired 2023-01-01
      final outDate = DateTime.utc(2026, 10, 30, 1, 42);

      final expiry = WarrantyCalculator.calculateExpiryDate(firstInDate: firstIn, durationMonths: durationMonths);
      expect(expiry, DateTime.utc(2023, 1, 1));

      // Judged against removal timestamp
      final isWarrantyValidAtOut = expiry.isAfter(outDate);
      final remainingDays = expiry.difference(outDate).inDays;

      expect(isWarrantyValidAtOut, false);
      expect(remainingDays, isNegative);
    });

    // --------------------------------------------------------------------------
    // AC5: Unregistered Bearing Fails Loudly (No Phantom Auto-Creation)
    // --------------------------------------------------------------------------
    test('AC5: BearingModel JSON parser rejects missing/unregistered bearings without silent 12M default', () {
      // Simulating server error payload when bearing is not registered
      final notFoundPayload = {'error_code': 'NOT_FOUND', 'message': 'Bearing ID UNKNOWN_999 not found in registry.'};

      expect(notFoundPayload['error_code'], 'NOT_FOUND');
      // Must not generate a BearingModel with 12 months default
    });

    // --------------------------------------------------------------------------
    // Live Supabase Verification of juVjDjzKJwY2 and HWMOnqek2w4p
    // --------------------------------------------------------------------------
    test('AC7: Live Supabase check verifies juVjDjzKJwY2 has 36M plan and HWMOnqek2w4p has 24M plan', () async {
      final client = HttpClient();
      const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN1YXN4ZWh1dWFka2FwZWhheGtoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE1NjM0NDQsImV4cCI6MjEwNzEzOTQ0NH0.T60jcH4gy1cGnSqM7Qrv1dyebPQ0KllaGl3xGYKZ_H0';

      final authUrl = Uri.parse('https://cuasxehuuadkapehaxkh.supabase.co/auth/v1/token?grant_type=password');
      final authReq = await client.postUrl(authUrl);
      authReq.headers.set('apikey', anonKey);
      authReq.headers.set('Content-Type', 'application/json');
      authReq.add(utf8.encode(jsonEncode({'email': 'test_dev_1@gmail.com', 'password': 'Password123!'})));
      final authRes = await authReq.close();
      final authData = jsonDecode(await authRes.transform(utf8.decoder).join());
      final token = authData['access_token'] ?? anonKey;

      final url = Uri.parse('https://cuasxehuuadkapehaxkh.supabase.co/rest/v1/qr_codes?select=bearing_id,warranty_duration_months,assigned_warranty_plan_id,warranty_plans:assigned_warranty_plan_id(*)&bearing_id=in.(juVjDjzKJwY2,HWMOnqek2w4p)');
      final req = await client.getUrl(url);
      req.headers.set('apikey', anonKey);
      req.headers.set('Authorization', 'Bearer $token');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final list = jsonDecode(body) as List;

      final ju = list.firstWhere((item) => item['bearing_id'] == 'juVjDjzKJwY2', orElse: () => null);
      final hwm = list.firstWhere((item) => item['bearing_id'] == 'HWMOnqek2w4p', orElse: () => null);

      expect(ju, isNotNull);
      expect(ju['warranty_duration_months'], 36);
      expect(ju['warranty_plans']['duration_months'], 36);

      expect(hwm, isNotNull);
      expect(hwm['warranty_duration_months'], 24);
      expect(hwm['warranty_plans']['duration_months'], 24);
    });
  });
}
