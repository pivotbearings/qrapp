import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/supabase_service.dart';
import '../../domain/models/bearing_track_result.dart';
import '../../domain/models/bearing_history_item.dart';
import '../../../qr_generation/domain/services/bearing_encryption_key_service.dart';
import '../../../qr_generation/data/repositories/qr_management_repository.dart';

import '../../../rewards/data/services/reward_service.dart';
import '../../../item_master/data/repositories/item_master_repository.dart';

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

    BearingTrackResult res;

    // 1. Authoritative Supabase RPC Execution
    if (SupabaseService.isInitialized) {
      try {
        final dynamic rpcRes = await SupabaseService.client.rpc(
          'track_bearing_scan',
          params: {
            'p_scanned_payload': cleanPayload,
            'p_notes': notes,
          },
        );

        if (rpcRes != null && rpcRes is Map) {
          final data = Map<String, dynamic>.from(rpcRes);
          await QrManagementRepository.loadFromLocalStorage();
          final localQr = QrManagementRepository.findQrRecord(cleanPayload) ??
              QrManagementRepository.findQrRecord(data['bearing_id']?.toString() ?? '');
          if (localQr != null) {
            data['model_number'] = localQr['model_number'] ?? data['model_number'];
            data['product_name'] = localQr['product_name'] ?? data['product_name'];
            data['duration_months'] = localQr['duration_months'] ?? data['duration_months'];
            data['batch_code'] = localQr['batch_code'] ?? data['batch_code'];
            data['plant_location'] = localQr['plant_location'] ?? data['plant_location'];
          }
          if (data['product_name'] == null && data['model_number'] != null) {
            final catItem = ItemMasterRepository().findByCode(data['model_number'].toString());
            if (catItem != null) {
              data['product_name'] = catItem.itemName;
            }
          }
          res = BearingTrackResult.fromJson(data, rawPayload: cleanPayload);
          // Sync with local & admin QR registry
          final bId = res.bearingId ?? _extractBearingId(cleanPayload);
          final prefs = await SharedPreferences.getInstance();
          final trackedList = prefs.getStringList('pbi_tracked_bearings_list') ?? [];
          if (!trackedList.contains(bId)) {
            trackedList.insert(0, bId);
            await prefs.setStringList('pbi_tracked_bearings_list', trackedList);
          }

          final upperBId = bId.toUpperCase();
          if (res.action == 'BEARING_OUT') {
            await prefs.setString('$_trackStatePrefix$bId', _finalOutState);
            await prefs.setString('$_trackStatePrefix$upperBId', _finalOutState);
            await prefs.setString('pbi_bearing_state_$bId', 'CURRENTLY_OUT');
            await prefs.setString('pbi_bearing_state_$upperBId', 'CURRENTLY_OUT');
            final outIso = (res.outTimestamp ?? DateTime.now()).toIso8601String();
            await prefs.setString('$_trackOutTimePrefix$bId', outIso);
            await prefs.setString('$_trackOutTimePrefix$upperBId', outIso);

            final historyKey = '$_trackHistoryPrefix$bId';
            List<dynamic> historyList = [];
            final histStr = prefs.getString(historyKey) ?? prefs.getString('$_trackHistoryPrefix$upperBId');
            if (histStr != null) {
              try {
                historyList = jsonDecode(histStr) as List<dynamic>;
              } catch (_) {}
            }
            final inIso = (res.inTimestamp ?? DateTime.now().subtract(const Duration(hours: 1))).toIso8601String();
            historyList.insert(0, {
              'cycle_number': res.cycleNumber,
              'in_timestamp': inIso,
              'out_timestamp': outIso,
              'duration_seconds': res.durationSeconds,
              'notes': res.notes ?? notes,
            });
            final encHist = jsonEncode(historyList);
            await prefs.setString(historyKey, encHist);
            await prefs.setString('$_trackHistoryPrefix$upperBId', encHist);
          } else if (res.action == 'BEARING_IN') {
            await prefs.setString('$_trackStatePrefix$bId', 'IN');
            await prefs.setString('$_trackStatePrefix$upperBId', 'IN');
            await prefs.setString('pbi_bearing_state_$bId', 'CURRENTLY_IN');
            await prefs.setString('pbi_bearing_state_$upperBId', 'CURRENTLY_IN');
            final inIso = (res.inTimestamp ?? DateTime.now()).toIso8601String();
            await prefs.setString('$_trackInTimePrefix$bId', inIso);
            await prefs.setString('$_trackInTimePrefix$upperBId', inIso);
          }
          await QrManagementRepository.syncBearingStateChange(
            bearingId: bId,
            newState: res.action == 'BEARING_IN' ? 'CURRENTLY_IN' : 'CURRENTLY_OUT',
            inTimestamp: res.inTimestamp,
            outTimestamp: res.outTimestamp,
          );
          return await _attachRewardIfApplicable(res, cleanPayload);
        }
      } catch (e) {
        debugPrint('Supabase RPC track_bearing_scan failed, falling back to local engine: $e');
      }
    }

    // 2. Resilient Local Lifecycle Engine (Offline / Local Fallback)
    res = await _localTrackScan(cleanPayload, notes: notes);
    return await _attachRewardIfApplicable(res, cleanPayload);
  }

  static Future<BearingTrackResult> _attachRewardIfApplicable(BearingTrackResult res, String cleanPayload) async {
    if (res.isValid && !res.isAlreadyOut) {
      try {
        final isClaimed = await RewardService.isBearingRewardClaimed(cleanPayload);
        if (isClaimed) {
          return res.copyWithReward(const RewardClaimResult(
            rewardAwarded: false,
            alreadyClaimed: true,
            message: 'First-scan reward has already been claimed for this bearing.',
          ));
        }
      } catch (e) {
        debugPrint('Track bearing reward check error: $e');
      }
    }
    return res;
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

  static Future<BearingTrackResult> _localTrackScan(String cleanPayload, {String? notes}) async {
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
    final notesKey = 'pbi_bearing_notes_$bearingId';

    if (notes != null && notes.trim().isNotEmpty) {
      await prefs.setString(notesKey, notes.trim());
    }
    final effectiveNotes = (notes != null && notes.trim().isNotEmpty)
        ? notes.trim()
        : prefs.getString(notesKey);

    final localState = prefs.getString(stateKey) ?? prefs.getString('pbi_bearing_state_$bearingId');
    final qrRecState = (QrManagementRepository.findQrRecord(bearingId) ??
        QrManagementRepository.findQrRecord(cleanPayload))?['current_lifecycle_state']?.toString();
    final currentState = (localState == 'IN' || localState == 'CURRENTLY_IN' || qrRecState == 'CURRENTLY_IN')
        ? 'IN'
        : (localState == _finalOutState || localState == 'CURRENTLY_OUT' || qrRecState == 'CURRENTLY_OUT')
            ? _finalOutState
            : (prefs.getString(stateKey) ?? 'OUT');
    final now = DateTime.now();

    // Resolve model info first
    final defaultItem = ItemMasterRepository().findByCode('B1') ??
        (ItemMasterRepository().getAllItems().isNotEmpty ? ItemMasterRepository().getAllItems().first : null);
    String model = defaultItem?.itemCode ?? 'B1';
    String batch = 'BATCH-ACTIVE';
    String plant = 'Plant 02 — Chakan Industrial Complex';
    String? productName = defaultItem?.itemName;
    int warrantyMonths = defaultItem?.defaultWarrantyMonths ?? 12;

    await QrManagementRepository.loadFromLocalStorage();
    final qrRec = QrManagementRepository.findQrRecord(bearingId) ??
        QrManagementRepository.findQrRecord(cleanPayload);
    if (qrRec != null) {
      final recModel = qrRec['model_number']?.toString();
      if (recModel != null && recModel != 'PBI-6204-ZZ') {
        model = recModel;
      }
      batch = qrRec['batch_code']?.toString() ?? batch;
      plant = qrRec['plant_location']?.toString() ?? plant;
      productName = qrRec['product_name']?.toString() ?? qrRec['item_name']?.toString() ?? productName;
      warrantyMonths = (qrRec['duration_months'] as num?)?.toInt() ?? warrantyMonths;
    } else if (isKnownSeed) {
      final info = knownRegisteredIds[bearingId]!;
      model = info['model']!;
      batch = info['batch']!;
      plant = info['plant']!;
    } else if (isGenuineKey) {
      final decoded = BearingEncryptionKeyService.decodeKey(bearingId);
      final modelTok = decoded['model_token'] ?? '6204';
      model = (modelTok == '6204' && defaultItem != null) ? defaultItem.itemCode : 'PBI-$modelTok-ZZ';
    }

    if (productName == null) {
      final catItem = ItemMasterRepository().findByCode(model);
      if (catItem != null) {
        productName = catItem.itemName;
        if (warrantyMonths == 6 && catItem.defaultWarrantyMonths > 0) {
          warrantyMonths = catItem.defaultWarrantyMonths;
        }
      }
    }

    final trackedList = prefs.getStringList('pbi_tracked_bearings_list') ?? [];
    if (!trackedList.contains(bearingId)) {
      trackedList.insert(0, bearingId);
      await prefs.setStringList('pbi_tracked_bearings_list', trackedList);
    }

    // Load past history
    List<BearingCycleRecord> history = [];
    final historyJson = prefs.getString(historyKey) ?? prefs.getString('$_trackHistoryPrefix${bearingId.toUpperCase()}');
    if (historyJson != null) {
      try {
        final decoded = jsonDecode(historyJson) as List;
        history = decoded.map((e) => BearingCycleRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      } catch (_) {}
    }

    // STRICT LIFECYCLE GUARD: Cycle 2 is forbidden! Once marked out, bearing is retired permanently
    final isPermanentlyOut = prefs.getBool('pbi_bearing_permanently_out_$bearingId') == true ||
        prefs.getBool('pbi_bearing_permanently_out_${bearingId.toUpperCase()}') == true ||
        localState == _finalOutState ||
        localState == 'CURRENTLY_OUT' ||
        qrRecState == 'CURRENTLY_OUT' ||
        prefs.getString(outTimeKey) != null ||
        prefs.getString('$_trackOutTimePrefix${bearingId.toUpperCase()}') != null;

    if (currentState != 'IN' && (isPermanentlyOut || history.isNotEmpty)) {
      DateTime? histIn = history.isNotEmpty ? history.first.inTimestamp : null;
      DateTime? histOut = history.isNotEmpty ? history.first.outTimestamp : null;
      if (histOut == null) {
        final outStr = prefs.getString(outTimeKey) ?? prefs.getString('$_trackOutTimePrefix${bearingId.toUpperCase()}');
        if (outStr != null) histOut = DateTime.tryParse(outStr)?.toLocal();
      }
      if (histIn == null) {
        final inStr = prefs.getString(inTimeKey) ?? prefs.getString('$_trackInTimePrefix${bearingId.toUpperCase()}');
        if (inStr != null) histIn = DateTime.tryParse(inStr)?.toLocal();
      }

      return BearingTrackResult.alreadyOut(
        bearingId: bearingId,
        inTimestamp: histIn,
        outTimestamp: histOut,
        modelNumber: model,
        productName: productName,
        message: 'This bearing has already completed its lifecycle and is permanently decommissioned. Cycle 2 is strictly prohibited.',
        rawPayload: cleanPayload,
      );
    }

    if (currentState == 'IN') {
      // =======================================================================
      // ACTION: BEARING OUT
      // =======================================================================
      DateTime inTime;
      final storedInTimeStr = prefs.getString(inTimeKey) ??
          prefs.getString('$_trackInTimePrefix${bearingId.toUpperCase()}') ??
          prefs.getString('$_trackInTimePrefix${cleanPayload.toUpperCase()}');
      if (storedInTimeStr != null) {
        inTime = DateTime.tryParse(storedInTimeStr)?.toLocal() ?? now.subtract(const Duration(hours: 1));
      } else {
        final qrInTime = qrRec?['first_in_timestamp'] ?? qrRec?['last_in_timestamp'];
        if (qrInTime != null) {
          inTime = DateTime.tryParse(qrInTime.toString())?.toLocal() ?? now;
        } else {
          inTime = now;
        }
      }

      final durSec = now.difference(inTime).inSeconds.abs();
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

      final upperId = bearingId.toUpperCase();
      // Persist to storage — set FINAL_OUT to permanently block further scans
      await prefs.setString(stateKey, _finalOutState);
      await prefs.setString('$_trackStatePrefix$upperId', _finalOutState);
      await prefs.setBool('pbi_bearing_permanently_out_$bearingId', true);
      await prefs.setBool('pbi_bearing_permanently_out_$upperId', true);
      await prefs.setString(outTimeKey, now.toIso8601String());
      await prefs.setString('$_trackOutTimePrefix$upperId', now.toIso8601String());
      await prefs.setString('pbi_bearing_state_$bearingId', 'CURRENTLY_OUT');
      await prefs.setString('pbi_bearing_state_$upperId', 'CURRENTLY_OUT');

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
        productName: productName,
        warrantyDurationMonths: warrantyMonths,
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
        notes: effectiveNotes,
        lifecycleHistory: history,
        rawPayload: cleanPayload,
      );
    } else {
      // =======================================================================
      // ACTION: BEARING IN
      // =======================================================================
      final upperId = bearingId.toUpperCase();
      await prefs.setString(stateKey, 'IN');
      await prefs.setString('$_trackStatePrefix$upperId', 'IN');
      await prefs.setString(inTimeKey, now.toIso8601String());
      await prefs.setString('$_trackInTimePrefix$upperId', now.toIso8601String());
      await prefs.setString('pbi_bearing_state_$bearingId', 'CURRENTLY_IN');
      await prefs.setString('pbi_bearing_state_$upperId', 'CURRENTLY_IN');

      if (SupabaseService.isInitialized) {
        try {
          await SupabaseService.client
              .from('qr_codes')
              .update({
                'current_lifecycle_state': 'CURRENTLY_IN',
                'first_in_timestamp': now.toIso8601String(),
                'last_in_timestamp': now.toIso8601String(),
                'updated_at': now.toIso8601String(),
              })
              .or('bearing_id.eq.$bearingId,payload_value.eq.$cleanPayload');
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
        productName: productName,
        warrantyDurationMonths: warrantyMonths,
        batchCode: batch,
        plantLocation: plant,
        cycleNumber: history.length + 1,
        inTimestamp: now,
        message: 'Bearing In recorded successfully. Usage tracking has started.',
        notes: effectiveNotes,
        lifecycleHistory: history,
        rawPayload: cleanPayload,
      );
    }
  }

  /// Persist or update notes for a bearing
  static Future<void> saveBearingNotes(String bearingId, String notes) async {
    final id = _extractBearingId(bearingId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pbi_bearing_notes_$id', notes.trim());

    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client
            .from('qr_codes')
            .update({
              'notes': notes.trim(),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('bearing_id', id);
      } catch (e) {
        debugPrint('saveBearingNotes Supabase sync notice: $e');
      }
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

  /// Fetches complete history of all bearings currently or previously marked as Bearing IN
  static Future<List<BearingHistoryItem>> fetchTrackInHistory() async {
    final List<BearingHistoryItem> items = [];
    final seen = <String>{};

    // 1. Supabase Query
    if (SupabaseService.isInitialized) {
      try {
        final res = await SupabaseService.client
            .from('qr_codes')
            .select('''
              bearing_id,
              model_number,
              first_in_timestamp,
              last_in_timestamp,
              current_lifecycle_state,
              qr_batches (batch_code)
            ''')
            .eq('current_lifecycle_state', 'CURRENTLY_IN')
            .order('last_in_timestamp', ascending: false);

        for (final row in res as List) {
          final m = Map<String, dynamic>.from(row as Map);
          final bid = m['bearing_id']?.toString() ?? '';
          if (bid.isEmpty) continue;
          final rawModel = m['model_number']?.toString() ?? 'PBI-MODEL';
          if (bid.toUpperCase().contains('XYZ') || rawModel.toUpperCase() == 'XYZ') continue;
          final batch = (m['qr_batches'] as Map<String, dynamic>?)?['batch_code']?.toString() ?? 'BATCH-ACTIVE';
          final rawInTs = m['last_in_timestamp']?.toString() ?? m['first_in_timestamp']?.toString();
          if (rawInTs == null || rawInTs.trim().isEmpty) continue;
          final inDt = DateTime.tryParse(rawInTs);
          if (inDt == null) continue;

          items.add(BearingHistoryItem(
            bearingId: bid,
            modelNumber: rawModel,
            batchCode: batch,
            inTimestamp: inDt,
            isOut: false,
          ));
          seen.add(bid.toUpperCase());
        }
      } catch (e) {
        debugPrint('Notice: Supabase fetchTrackInHistory query: $e');
      }
    }

    // 2. Local SharedPreferences fallback & merge
    try {
      final prefs = await SharedPreferences.getInstance();
      final trackedIds = prefs.getStringList('pbi_tracked_bearings_list') ?? [];
      await QrManagementRepository.loadFromLocalStorage();

      // Sanitize trackedIds to purge any legacy mock XYZ IDs
      final sanitizedTrackedIds = <String>[];
      bool hadMockIds = false;
      for (final id in trackedIds) {
        if (id.toUpperCase().contains('XYZ')) {
          hadMockIds = true;
          prefs.remove('$_trackStatePrefix$id');
          prefs.remove('pbi_bearing_state_$id');
          prefs.remove('$_trackInTimePrefix$id');
          prefs.remove('$_trackOutTimePrefix$id');
          prefs.remove('$_trackHistoryPrefix$id');
          prefs.remove('pbi_bearing_notes_$id');
        } else {
          sanitizedTrackedIds.add(id);
        }
      }
      if (hadMockIds) {
        await prefs.setStringList('pbi_tracked_bearings_list', sanitizedTrackedIds);
      }

      for (final id in sanitizedTrackedIds) {
        if (seen.contains(id.toUpperCase())) continue;
        final state = prefs.getString('$_trackStatePrefix$id') ?? prefs.getString('pbi_bearing_state_$id');
        if (state == 'IN' || state == 'CURRENTLY_IN') {
          final inStr = prefs.getString('$_trackInTimePrefix$id');
          if (inStr == null || inStr.trim().isEmpty) continue;
          final inDt = DateTime.tryParse(inStr);
          if (inDt == null) continue;
          final qr = QrManagementRepository.findQrRecord(id);
          final model = (qr?['model_number'] != null && qr?['model_number'] != 'PBI-6204-ZZ')
              ? qr!['model_number'].toString()
              : (ItemMasterRepository().findByCode('B1')?.itemCode ?? 'B1');
          if (id.toUpperCase().contains('XYZ') || model.toUpperCase() == 'XYZ') continue;
          final batch = qr?['batch_code']?.toString() ?? 'BATCH-ACTIVE';
          final notes = prefs.getString('pbi_bearing_notes_$id');

          items.add(BearingHistoryItem(
            bearingId: id,
            modelNumber: model,
            batchCode: batch,
            inTimestamp: inDt,
            notes: notes,
            isOut: false,
          ));
          seen.add(id.toUpperCase());
        }
      }
    } catch (e) {
      debugPrint('Notice: local fetchTrackInHistory query: $e');
    }

    // Sort newest inTimestamp first
    items.sort((a, b) => b.inTimestamp.compareTo(a.inTimestamp));
    return items;
  }

  /// Fetches complete history of all bearings marked as Bearing OUT with operating duration
  static Future<List<BearingHistoryItem>> fetchTrackOutHistory() async {
    final List<BearingHistoryItem> items = [];
    final seenCycles = <String>{};

    // 1. Supabase Query for completed cycles
    if (SupabaseService.isInitialized) {
      try {
        final res = await SupabaseService.client
            .from('bearing_installation_cycles')
            .select('''
              id,
              cycle_number,
              in_timestamp,
              out_timestamp,
              operating_duration_seconds,
              notes,
              qr_codes (bearing_id, model_number, qr_batches (batch_code))
            ''')
            .eq('is_cycle_closed', true)
            .order('out_timestamp', ascending: false);

        for (final row in res as List) {
          final m = Map<String, dynamic>.from(row as Map);
          final qr = m['qr_codes'] as Map<String, dynamic>?;
          final bid = qr?['bearing_id']?.toString() ?? '';
          if (bid.isEmpty) continue;
          final modelNum = qr?['model_number']?.toString() ?? 'PBI-MODEL';
          if (bid.toUpperCase().contains('XYZ') || modelNum.toUpperCase() == 'XYZ') continue;
          final batch = (qr?['qr_batches'] as Map<String, dynamic>?)?['batch_code']?.toString() ?? 'BATCH-ACTIVE';
          final rawIn = m['in_timestamp']?.toString();
          final rawOut = m['out_timestamp']?.toString();
          if (rawIn == null || rawIn.trim().isEmpty || rawOut == null || rawOut.trim().isEmpty) continue;
          final inDt = DateTime.tryParse(rawIn);
          final outDt = DateTime.tryParse(rawOut);
          if (inDt == null || outDt == null) continue;
          final dur = (m['operating_duration_seconds'] as num?)?.toInt() ?? outDt.difference(inDt).inSeconds;
          final note = m['notes']?.toString();

          final key = '$bid-${outDt.millisecondsSinceEpoch}';
          if (!seenCycles.contains(key)) {
            items.add(BearingHistoryItem(
              bearingId: bid,
              modelNumber: modelNum,
              batchCode: batch,
              inTimestamp: inDt,
              outTimestamp: outDt,
              durationSeconds: dur,
              notes: note,
              isOut: true,
            ));
            seenCycles.add(key);
          }
        }
      } catch (e) {
        debugPrint('Notice: Supabase fetchTrackOutHistory query: $e');
      }
    }

    // 2. Local SharedPreferences fallback & merge
    try {
      final prefs = await SharedPreferences.getInstance();
      final trackedIds = prefs.getStringList('pbi_tracked_bearings_list') ?? [];
      await QrManagementRepository.loadFromLocalStorage();

      for (final id in trackedIds) {
        if (id.toUpperCase().contains('XYZ')) continue;
        final qr = QrManagementRepository.findQrRecord(id);
        final model = (qr?['model_number'] != null && qr?['model_number'] != 'PBI-6204-ZZ')
            ? qr!['model_number'].toString()
            : (ItemMasterRepository().findByCode('B1')?.itemCode ?? 'B1');
        if (model.toUpperCase() == 'XYZ') continue;
        final batch = qr?['batch_code']?.toString() ?? 'BATCH-ACTIVE';

        // Check cycle history list
        final histJson = prefs.getString('$_trackHistoryPrefix$id');
        if (histJson != null) {
          try {
            final decoded = jsonDecode(histJson) as List;
            for (final entry in decoded) {
              final em = Map<String, dynamic>.from(entry as Map);
              final rawIn = em['in_timestamp']?.toString();
              final rawOut = em['out_timestamp']?.toString();
              if (rawIn == null || rawIn.trim().isEmpty || rawOut == null || rawOut.trim().isEmpty) continue;
              final inDt = DateTime.tryParse(rawIn);
              final outDt = DateTime.tryParse(rawOut);
              if (inDt == null || outDt == null) continue;
              final dur = (em['duration_seconds'] as num?)?.toInt() ?? outDt.difference(inDt).inSeconds;
              final note = em['notes']?.toString() ?? prefs.getString('pbi_bearing_notes_$id');

              final key = '$id-${outDt.millisecondsSinceEpoch}';
              if (!seenCycles.contains(key)) {
                items.add(BearingHistoryItem(
                  bearingId: id,
                  modelNumber: model,
                  batchCode: batch,
                  inTimestamp: inDt,
                  outTimestamp: outDt,
                  durationSeconds: dur,
                  notes: note,
                  isOut: true,
                ));
                seenCycles.add(key);
              }
            }
          } catch (_) {}
        }

        // Also check single out state
        final state = prefs.getString('$_trackStatePrefix$id') ?? prefs.getString('pbi_bearing_state_$id');
        if (state == _finalOutState || state == 'OUT' || state == 'CURRENTLY_OUT') {
          final outStr = prefs.getString('$_trackOutTimePrefix$id');
          final inStr = prefs.getString('$_trackInTimePrefix$id');
          if (outStr != null && inStr != null) {
            final outDt = DateTime.tryParse(outStr);
            final inDt = DateTime.tryParse(inStr);
            if (outDt != null && inDt != null) {
              final key = '$id-${outDt.millisecondsSinceEpoch}';
              if (!seenCycles.contains(key)) {
                items.add(BearingHistoryItem(
                  bearingId: id,
                  modelNumber: model,
                  batchCode: batch,
                  inTimestamp: inDt,
                  outTimestamp: outDt,
                  durationSeconds: outDt.difference(inDt).inSeconds,
                  notes: prefs.getString('pbi_bearing_notes_$id'),
                  isOut: true,
                ));
                seenCycles.add(key);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Notice: local fetchTrackOutHistory query: $e');
    }

    // Sort newest outTimestamp first
    items.sort((a, b) => (b.outTimestamp ?? b.inTimestamp).compareTo(a.outTimestamp ?? a.inTimestamp));
    return items;
  }
}
