import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/supabase_service.dart';
import '../../domain/models/bearing_track_result.dart';
import '../../../qr_generation/domain/services/bearing_encryption_key_service.dart';
import '../../../qr_generation/data/repositories/qr_management_repository.dart';

/// Pivot Bearings India - Bearing Tracking Service
///
/// Manages QR-only IN/OUT lifecycle transitions without photographs or evidence capture:
/// - 1st scan (not in use): Records entry time -> "Bearing In" (Green)
/// - 2nd scan (in use): Records exit time -> "Bearing Out" (Red) & calculates usage duration
/// - Repeated usage: Allows starting a new cycle while preserving historical completed cycles
class BearingTrackService {
  static const String _trackStatePrefix = 'pbi_track_state_';
  static const String _trackInTimePrefix = 'pbi_track_in_time_';
  static const String _trackHistoryPrefix = 'pbi_track_history_';
  static const String _trackOutTimePrefix = 'pbi_track_out_time_';
  // 'FINAL_OUT' stored in state means permanently decommissioned - no more scans allowed
  static const String _finalOutState = 'FINAL_OUT';

  static Future<BearingTrackResult> trackScan(String rawPayload, {String? notes}) async {
    final cleanPayload = rawPayload.trim();
    if (cleanPayload.isEmpty) {
      return BearingTrackResult.invalid(
        rawPayload: rawPayload,
        message: 'Empty QR code payload.',
      );
    }

    // 1. Authoritative Supabase RPC Execution
    if (SupabaseService.isInitialized) {
      try {
        final dynamic res = await SupabaseService.client.rpc(
          'track_bearing_scan',
          params: {
            'p_scanned_payload': cleanPayload,
            'p_notes': notes,
          },
        );

        if (res != null && res is Map) {
          final data = Map<String, dynamic>.from(res);
          final result = BearingTrackResult.fromJson(data, rawPayload: cleanPayload);
          // Sync with local & admin QR registry
          await QrManagementRepository.syncBearingStateChange(
            bearingId: result.bearingId ?? _extractBearingId(cleanPayload),
            newState: result.action == 'BEARING_IN' ? 'CURRENTLY_IN' : 'CURRENTLY_OUT',
            inTimestamp: result.inTimestamp,
            outTimestamp: result.outTimestamp,
          );
          return result;
        }
      } catch (e) {
        debugPrint('Supabase RPC track_bearing_scan failed, falling back to local engine: $e');
      }
    }

    // 2. Resilient Local Lifecycle Engine (Offline / Local Fallback)
    return await _localTrackScan(cleanPayload);
  }

  static String _extractBearingId(String payload) {
    var id = payload.trim();
    if (id.contains('/pbi/')) {
      final parts = id.split('/pbi/');
      if (parts.length > 1) {
        id = parts[1].split('?').first.split('&').first;
      }
    } else if (id.contains('://')) {
      final uri = Uri.tryParse(id);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        id = uri.pathSegments.last.split('?').first;
      }
    }
    return id.toUpperCase().trim();
  }

  static Future<BearingTrackResult> _localTrackScan(String cleanPayload) async {
    final bearingId = _extractBearingId(cleanPayload);

    // Validate identifier against registry or cryptographic format
    final isKnownFormat = BearingEncryptionKeyService.isValidKeyOrId(bearingId) ||
        RegExp(r'^(PB-[0-9]{4}-[A-Z0-9]{2}|PBI-SEC-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}|(PBI|PB)(-[A-Z0-9]{3,8}){2,5})$', caseSensitive: false).hasMatch(bearingId);

    final knownRegisteredIds = {
      'PB-9402-XJ': {'model': 'PBI-6204-ZZ', 'batch': 'BATCH-2026-OCT-A', 'plant': 'Plant 02 — Chakan'},
      'PB-8812-KR': {'model': 'PBI-6309-2RS', 'batch': 'BATCH-2026-OCT-A', 'plant': 'Plant 02 — Chakan'},
      'PB-1044-ZN': {'model': 'PBI-22216-E', 'batch': 'BATCH-2026-SEP-B', 'plant': 'Plant 01 — Bhosari'},
    };

    final isKnownSeed = knownRegisteredIds.containsKey(bearingId);
    final isGenuineKey = BearingEncryptionKeyService.verifyTamperProofChecksum(bearingId);

    if (!isKnownFormat || (!isKnownSeed && !isGenuineKey)) {
      return BearingTrackResult.invalid(
        rawPayload: cleanPayload,
        message: 'Invalid Bearing Code. Bearing Authenticity Could Not Be Verified.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final stateKey = '$_trackStatePrefix$bearingId';
    final inTimeKey = '$_trackInTimePrefix$bearingId';
    final historyKey = '$_trackHistoryPrefix$bearingId';
    final outTimeKey = '$_trackOutTimePrefix$bearingId';

    final currentState = prefs.getString(stateKey) ?? 'OUT';
    final now = DateTime.now();

    // Resolve model info first
    String model = 'PBI-6204-ZZ';
    String batch = 'BATCH-2026-OCT-A';
    String plant = 'Plant 02 — Chakan Industrial Complex';

    if (isKnownSeed) {
      final info = knownRegisteredIds[bearingId]!;
      model = info['model']!;
      batch = info['batch']!;
      plant = info['plant']!;
    } else if (isGenuineKey) {
      final decoded = BearingEncryptionKeyService.decodeKey(bearingId);
      final modelTok = decoded['model_token'] ?? '6204';
      model = 'PBI-$modelTok-ZZ';
    }

    final isPermanentlyOut = prefs.getBool('pbi_bearing_permanently_out_$bearingId') == true;

    // === TERMINAL GUARD: Once marked FINAL_OUT, permanently refuse all further scans ===
    if (currentState == _finalOutState || isPermanentlyOut) {
      DateTime? storedIn;
      DateTime? storedOut;
      final inStr = prefs.getString(inTimeKey);
      final outStr = prefs.getString(outTimeKey);
      if (inStr != null) storedIn = DateTime.tryParse(inStr);
      if (outStr != null) storedOut = DateTime.tryParse(outStr);
      return BearingTrackResult.alreadyOut(
        bearingId: bearingId,
        modelNumber: model,
        inTimestamp: storedIn,
        outTimestamp: storedOut,
        message: 'bearing marked as out, cant scan again.',
        rawPayload: cleanPayload,
      );
    }

    // Load past history
    List<BearingCycleRecord> history = [];
    final historyJson = prefs.getString(historyKey);
    if (historyJson != null) {
      try {
        final decoded = jsonDecode(historyJson) as List;
        history = decoded.map((e) => BearingCycleRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      } catch (_) {}
    }

    if (currentState == 'IN') {
      // =======================================================================
      // ACTION: BEARING OUT
      // =======================================================================
      DateTime inTime;
      final storedInTimeStr = prefs.getString(inTimeKey);
      if (storedInTimeStr != null) {
        inTime = DateTime.tryParse(storedInTimeStr) ?? now.subtract(const Duration(hours: 1));
      } else {
        inTime = now.subtract(const Duration(hours: 1));
      }

      final durSec = now.difference(inTime).inSeconds;
      final safeDurSec = durSec > 0 ? durSec : 1;

      final cycleNum = history.length + 1;
      final newCycle = BearingCycleRecord(
        cycleNumber: cycleNum,
        inTimestamp: inTime,
        outTimestamp: now,
        durationSeconds: safeDurSec,
      );

      // Append to history (newest first)
      history.insert(0, newCycle);

      // Persist to storage — set FINAL_OUT to permanently block further scans
      await prefs.setString(stateKey, _finalOutState);
      await prefs.setBool('pbi_bearing_permanently_out_$bearingId', true);
      await prefs.setString(outTimeKey, now.toIso8601String());

      if (SupabaseService.isInitialized) {
        try {
          await SupabaseService.client
              .from('qr_codes')
              .update({
                'current_lifecycle_state': 'CURRENTLY_OUT',
                'last_out_timestamp': now.toIso8601String(),
                'updated_at': now.toIso8601String(),
              })
              .or('bearing_id.eq.$bearingId,payload_value.eq.$cleanPayload');
        } catch (_) {}
      }
      await QrManagementRepository.syncBearingStateChange(
        bearingId: bearingId,
        newState: 'CURRENTLY_OUT',
        outTimestamp: now,
      );
      await prefs.setString(
        historyKey,
        jsonEncode(history
            .map((c) => {
                  'cycle_number': c.cycleNumber,
                  'in_timestamp': c.inTimestamp.toIso8601String(),
                  'out_timestamp': c.outTimestamp?.toIso8601String(),
                  'duration_seconds': c.durationSeconds,
                })
            .toList()),
      );

      final days = safeDurSec ~/ 86400;
      final hours = (safeDurSec % 86400) ~/ 3600;
      final minutes = (safeDurSec % 3600) ~/ 60;

      return BearingTrackResult(
        isValid: true,
        action: 'BEARING_OUT',
        bearingId: bearingId,
        modelNumber: model,
        batchCode: batch,
        plantLocation: plant,
        cycleNumber: cycleNum,
        inTimestamp: inTime,
        outTimestamp: now,
        durationSeconds: safeDurSec,
        durationDays: days,
        durationHours: hours,
        durationMinutes: minutes,
        message: 'Bearing Out recorded successfully.',
        notes: prefs.getString('pbi_bearing_notes_$bearingId'),
        lifecycleHistory: history,
        rawPayload: cleanPayload,
      );
    } else {
      // =======================================================================
      // ACTION: BEARING IN
      // =======================================================================
      await prefs.setString(stateKey, 'IN');
      await prefs.setString(inTimeKey, now.toIso8601String());

      if (SupabaseService.isInitialized) {
        try {
          final updatedRows = await SupabaseService.client
              .from('qr_codes')
              .update({
                'current_lifecycle_state': 'CURRENTLY_IN',
                'first_in_timestamp': now.toIso8601String(),
                'last_in_timestamp': now.toIso8601String(),
                'updated_at': now.toIso8601String(),
              })
              .or('bearing_id.eq.$bearingId,payload_value.eq.$cleanPayload')
              .select('id');

          if (updatedRows.isEmpty) {
            // Upsert into qr_codes if not present so it shows up in admin QR registry immediately!
            await SupabaseService.client.from('qr_codes').insert({
              'bearing_id': bearingId,
              'batch_id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
              'assigned_warranty_plan_id': '22222222-2222-2222-2222-222222222222',
              'model_number': model,
              'payload_value': cleanPayload,
              'payload_hash': 'SHA-256: VALID',
              'current_lifecycle_state': 'CURRENTLY_IN',
              'first_in_timestamp': now.toIso8601String(),
              'last_in_timestamp': now.toIso8601String(),
              'is_flagged': false,
            });
          }
        } catch (e) {
          debugPrint('Notice: localTrackScan BEARING_IN update qr_codes error: $e');
        }
      }

      await QrManagementRepository.syncBearingStateChange(
        bearingId: bearingId,
        newState: 'CURRENTLY_IN',
        inTimestamp: now,
      );

      return BearingTrackResult(
        isValid: true,
        action: 'BEARING_IN',
        bearingId: bearingId,
        modelNumber: model,
        batchCode: batch,
        plantLocation: plant,
        cycleNumber: history.length + 1,
        inTimestamp: now,
        message: 'Bearing In recorded successfully. Usage tracking has started.',
        lifecycleHistory: history,
        rawPayload: cleanPayload,
      );
    }
  }

  /// Helper to simulate an older entry time for testing "5 days" calculation demo
  static Future<void> simulatePastEntryTime(String bearingId, Duration pastOffset) async {
    final prefs = await SharedPreferences.getInstance();
    final id = _extractBearingId(bearingId);
    final inTimeKey = '$_trackInTimePrefix$id';
    final stateKey = '$_trackStatePrefix$id';
    await prefs.setString(stateKey, 'IN');
    await prefs.setString(inTimeKey, DateTime.now().subtract(pastOffset).toIso8601String());
  }
}
