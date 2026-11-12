import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/auth/auth_controller.dart';
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

  static String? _cleanNote(String? value) {
    if (value == null) return null;
    final t = value.trim();
    return t.isEmpty ? null : t;
  }

  static String? _readPrefNotes(
    SharedPreferences prefs,
    String bearingId,
    List<String> prefixes,
  ) {
    final trimmed = bearingId.trim();
    if (trimmed.isEmpty) return null;
    final upper = trimmed.toUpperCase();
    for (final prefix in prefixes) {
      final val = _cleanNote(prefs.getString('$prefix$trimmed')) ??
          _cleanNote(prefs.getString('$prefix$upper'));
      if (val != null) return val;
    }
    return null;
  }

  static (String?, String?) _splitLegacyOutNotes(String? raw) {
    final clean = _cleanNote(raw);
    if (clean == null || !clean.contains(' | Out: ')) return (null, null);
    final parts = clean.split(' | Out: ');
    return (_cleanNote(parts.first), _cleanNote(parts.sublist(1).join(' | Out: ')));
  }

  static Future<void> _writePrefNotes(
    SharedPreferences prefs,
    String bearingId, {
    String? inNotes,
    String? outNotes,
  }) async {
    final trimmed = bearingId.trim();
    if (trimmed.isEmpty) return;
    final upper = trimmed.toUpperCase();
    final cleanIn = _cleanNote(inNotes);
    final cleanOut = _cleanNote(outNotes);

    if (cleanIn != null) {
      await prefs.setString('pbi_bearing_in_notes_$trimmed', cleanIn);
      await prefs.setString('pbi_bearing_in_notes_$upper', cleanIn);
      if (cleanOut == null) {
        await prefs.setString('pbi_bearing_notes_$trimmed', cleanIn);
        await prefs.setString('pbi_bearing_notes_$upper', cleanIn);
      }
    }
    if (cleanOut != null) {
      await prefs.setString('pbi_bearing_out_notes_$trimmed', cleanOut);
      await prefs.setString('pbi_bearing_out_notes_$upper', cleanOut);
      await prefs.setString('pbi_mark_out_notes_$trimmed', cleanOut);
      await prefs.setString('pbi_mark_out_notes_$upper', cleanOut);
    }
  }

  static Future<void> _syncNotesToSupabase(
    String bearingId, {
    String? inNotes,
    String? outNotes,
  }) async {
    if (!SupabaseService.isInitialized) return;
    final cleanIn = _cleanNote(inNotes);
    final cleanOut = _cleanNote(outNotes);
    if (cleanIn == null && cleanOut == null) return;
    try {
      final updateMap = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (cleanIn != null) updateMap['in_notes'] = cleanIn;
      if (cleanOut != null) updateMap['out_notes'] = cleanOut;

      final qrRow = await SupabaseService.client
          .from('qr_codes')
          .select('id')
          .ilike('bearing_id', bearingId.trim())
          .maybeSingle();
      if (qrRow != null && qrRow['id'] != null) {
        final qrUuid = qrRow['id'].toString();
        await SupabaseService.client
            .from('qr_codes')
            .update(updateMap)
            .eq('id', qrUuid);

        final latestCycle = await SupabaseService.client
            .from('bearing_installation_cycles')
            .select('id')
            .eq('qr_code_id', qrUuid)
            .order('cycle_number', ascending: false)
            .limit(1)
            .maybeSingle();
        if (latestCycle != null && latestCycle['id'] != null) {
          await SupabaseService.client
              .from('bearing_installation_cycles')
              .update(updateMap)
              .eq('id', latestCycle['id']);
        }
      }
    } catch (e) {
      debugPrint('BearingTrackService._syncNotesToSupabase notice: $e');
    }
  }

  /// Resolves Mark In and Mark Out notes for any bearing ID from local prefs and Supabase.
  static Future<({String? inNotes, String? outNotes, String? legacyNotes})> fetchBearingInOutNotes(
    String bearingId, {
    bool queryRemoteIfMissing = true,
  }) async {
    final cleanId = _extractRawBearingId(bearingId);
    final prefs = await SharedPreferences.getInstance();
    var inNote = _readPrefNotes(prefs, cleanId, const ['pbi_bearing_in_notes_']);
    var outNote = _readPrefNotes(prefs, cleanId, const [
      'pbi_bearing_out_notes_',
      'pbi_mark_out_notes_',
    ]);
    var legacyNote = _readPrefNotes(prefs, cleanId, const ['pbi_bearing_notes_']);

    if (queryRemoteIfMissing &&
        SupabaseService.isInitialized &&
        cleanId.isNotEmpty &&
        (inNote == null || outNote == null)) {
      try {
        final qrRow = await SupabaseService.client
            .from('qr_codes')
            .select('id, in_notes, out_notes, notes')
            .ilike('bearing_id', cleanId)
            .maybeSingle();
        if (qrRow != null) {
          inNote ??= _cleanNote(qrRow['in_notes']?.toString());
          outNote ??= _cleanNote(qrRow['out_notes']?.toString());
          legacyNote ??= _cleanNote(qrRow['notes']?.toString());

          final qrUuid = qrRow['id']?.toString();
          if (qrUuid != null && (inNote == null || outNote == null)) {
            final cycleRow = await SupabaseService.client
                .from('bearing_installation_cycles')
                .select('in_notes, out_notes, notes')
                .eq('qr_code_id', qrUuid)
                .order('cycle_number', ascending: false)
                .limit(1)
                .maybeSingle();
            if (cycleRow != null) {
              final cycleRaw = _cleanNote(cycleRow['notes']?.toString());
              final (splitIn, splitOut) = _splitLegacyOutNotes(cycleRaw);
              inNote ??= _cleanNote(cycleRow['in_notes']?.toString()) ?? splitIn;
              outNote ??= _cleanNote(cycleRow['out_notes']?.toString()) ?? splitOut;
              legacyNote ??= cycleRaw;
            }
          }
        }
      } catch (e) {
        debugPrint('fetchBearingInOutNotes Supabase notice: $e');
      }
    }

    if (legacyNote != null && legacyNote.contains(' | Out: ')) {
      final (splitIn, splitOut) = _splitLegacyOutNotes(legacyNote);
      inNote ??= splitIn;
      outNote ??= splitOut;
    }

    if (inNote == null && legacyNote != null && outNote != legacyNote) {
      inNote = legacyNote;
    }

    return (inNotes: inNote, outNotes: outNote, legacyNotes: legacyNote);
  }

  static String _extractRawBearingId(String payload) {
    var id = payload.trim();
    if (id.contains('/pbi/')) {
      final parts = id.split('/pbi/');
      if (parts.length > 1) {
        id = parts[1].split('?').first.split('&').first;
      }
    } else if (id.contains('/verify/')) {
      final parts = id.split('/verify/');
      if (parts.length > 1) {
        id = parts[1].split('?').first.split('&').first;
      }
    } else if (id.contains('://')) {
      final uri = Uri.tryParse(id);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        id = uri.pathSegments.last.split('?').first.split('&').first;
      }
    }
    try {
      id = Uri.decodeComponent(id);
    } catch (_) {}
    return id.trim();
  }

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
          final submittedNote = _cleanNote(notes);
          String? resolvedInNote = _cleanNote(res.inNotes);
          String? resolvedOutNote = _cleanNote(res.outNotes);

          if (res.action == 'BEARING_OUT') {
            await prefs.setString('$_trackStatePrefix$bId', _finalOutState);
            await prefs.setString('$_trackStatePrefix$upperBId', _finalOutState);
            await prefs.setString('pbi_bearing_state_$bId', 'CURRENTLY_OUT');
            await prefs.setString('pbi_bearing_state_$upperBId', 'CURRENTLY_OUT');
            final outIso = (res.outTimestamp ?? DateTime.now()).toIso8601String();
            await prefs.setString('$_trackOutTimePrefix$bId', outIso);
            await prefs.setString('$_trackOutTimePrefix$upperBId', outIso);

            resolvedOutNote ??= submittedNote ??
                _readPrefNotes(prefs, bId, const ['pbi_bearing_out_notes_', 'pbi_mark_out_notes_']);
            final (splitIn, splitOut) = _splitLegacyOutNotes(res.notes);
            resolvedInNote ??= splitIn ??
                _readPrefNotes(prefs, bId, const ['pbi_bearing_in_notes_', 'pbi_bearing_notes_']);
            resolvedOutNote ??= splitOut;
            // track_bearing_scan RPC returns previous active cycle notes as `res.notes` when set
            final cleanResNote = _cleanNote(res.notes);
            if (resolvedInNote == null && cleanResNote != null && cleanResNote != submittedNote) {
              resolvedInNote = cleanResNote;
            }
            if (resolvedInNote == null || resolvedOutNote == null) {
              final fetched = await fetchBearingInOutNotes(bId);
              resolvedInNote ??= fetched.inNotes;
              resolvedOutNote ??= fetched.outNotes;
            }
            await _writePrefNotes(
              prefs,
              bId,
              inNotes: resolvedInNote,
              outNotes: resolvedOutNote,
            );
            await _syncNotesToSupabase(bId, outNotes: resolvedOutNote);
            res = BearingTrackResult(
              isValid: res.isValid,
              action: res.action,
              bearingId: res.bearingId,
              modelNumber: res.modelNumber,
              productName: res.productName,
              batchCode: res.batchCode,
              plantLocation: res.plantLocation,
              cycleNumber: res.cycleNumber,
              inTimestamp: res.inTimestamp,
              outTimestamp: res.outTimestamp,
              durationSeconds: res.durationSeconds,
              durationDays: res.durationDays,
              durationHours: res.durationHours,
              durationMinutes: res.durationMinutes,
              warrantyDurationMonths: res.warrantyDurationMonths,
              warrantyExpiryTimestamp: res.warrantyExpiryTimestamp,
              message: res.message,
              notes: resolvedOutNote ?? resolvedInNote ?? res.notes,
              inNotes: resolvedInNote,
              outNotes: resolvedOutNote,
              lifecycleHistory: res.lifecycleHistory,
              rawPayload: res.rawPayload,
              rewardClaim: res.rewardClaim,
            );

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
              'in_notes': resolvedInNote,
              'out_notes': resolvedOutNote,
              'notes': resolvedOutNote ?? resolvedInNote ?? res.notes,
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

            resolvedInNote ??= submittedNote ??
                _cleanNote(res.notes) ??
                _readPrefNotes(prefs, bId, const ['pbi_bearing_in_notes_', 'pbi_bearing_notes_']);
            if (resolvedInNote != null) {
              await _writePrefNotes(prefs, bId, inNotes: resolvedInNote);
              await _syncNotesToSupabase(bId, inNotes: resolvedInNote);
              res = res.copyWithNotes(resolvedInNote, isOut: false, inNotes: resolvedInNote);
            }
          } else if (res.action == 'ALREADY_OUT') {
            final fetched = await fetchBearingInOutNotes(bId);
            resolvedInNote ??= fetched.inNotes;
            resolvedOutNote ??= fetched.outNotes;
            await _writePrefNotes(prefs, bId, inNotes: resolvedInNote, outNotes: resolvedOutNote);
            res = BearingTrackResult.alreadyOut(
              bearingId: bId,
              inTimestamp: res.inTimestamp,
              outTimestamp: res.outTimestamp,
              modelNumber: res.modelNumber,
              productName: res.productName,
              warrantyDurationMonths: res.warrantyDurationMonths,
              warrantyExpiryTimestamp: res.warrantyExpiryTimestamp,
              message: res.message,
              inNotes: resolvedInNote,
              outNotes: resolvedOutNote,
              rawPayload: res.rawPayload,
            );
          }
          final results = await Future.wait<dynamic>([
            QrManagementRepository.syncBearingStateChange(
              bearingId: bId,
              newState: res.action == 'BEARING_IN' ? 'CURRENTLY_IN' : 'CURRENTLY_OUT',
              inTimestamp: res.inTimestamp,
              outTimestamp: res.outTimestamp,
            ),
            _attachRewardIfApplicable(res, cleanPayload),
          ]);
          return results[1] as BearingTrackResult;
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
        final auth = AuthController.instance;
        if (!auth.isRewardEligible) {
          return res.copyWithReward(const RewardClaimResult(
            rewardAwarded: false,
            isUserBlocked: true,
            message: 'Bearing verified authentic. Promotional reward points are currently inactive for this account profile.',
          ));
        }

        final claimBearingId = (res.bearingId != null && res.bearingId!.isNotEmpty)
            ? res.bearingId!
            : cleanPayload;
        final claim = await RewardService.claimBearingScanReward(
          rawPayloadOrId: claimBearingId,
          sourceModule: 'TRACK_BEARING',
        );
        return res.copyWithReward(claim);
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
    final rawBearingId = _extractRawBearingId(cleanPayload);
    final storageId = rawBearingId.isNotEmpty ? rawBearingId : bearingId;
    final stateKey = '$_trackStatePrefix$bearingId';
    final inTimeKey = '$_trackInTimePrefix$bearingId';
    final historyKey = '$_trackHistoryPrefix$bearingId';
    final outTimeKey = '$_trackOutTimePrefix$bearingId';

    final localState = prefs.getString(stateKey) ??
        prefs.getString('pbi_bearing_state_$bearingId') ??
        prefs.getString('$_trackStatePrefix$storageId') ??
        prefs.getString('pbi_bearing_state_$storageId');
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

      final existingInNote = _readPrefNotes(prefs, storageId, const [
            'pbi_bearing_in_notes_',
            'pbi_bearing_notes_',
          ]) ??
          _cleanNote(qrRec?['in_notes']?.toString());
      final existingOutNote = _readPrefNotes(prefs, storageId, const [
            'pbi_bearing_out_notes_',
            'pbi_mark_out_notes_',
          ]) ??
          _cleanNote(qrRec?['out_notes']?.toString());

      return BearingTrackResult.alreadyOut(
        bearingId: bearingId,
        inTimestamp: histIn,
        outTimestamp: histOut,
        modelNumber: model,
        productName: productName,
        inNotes: existingInNote,
        outNotes: existingOutNote,
        message: 'This bearing has already completed its lifecycle and is permanently decommissioned. Cycle 2 is strictly prohibited.',
        rawPayload: cleanPayload,
      );
    }

    if (currentState == 'IN') {
      // =======================================================================
      // ACTION: BEARING OUT
      // =======================================================================
      final resolvedInNote = _readPrefNotes(prefs, storageId, const [
            'pbi_bearing_in_notes_',
            'pbi_bearing_notes_',
          ]) ??
          _cleanNote(qrRec?['in_notes']?.toString()) ??
          _cleanNote(qrRec?['notes']?.toString());
      final resolvedOutNote = _cleanNote(notes) ??
          _readPrefNotes(prefs, storageId, const [
            'pbi_bearing_out_notes_',
            'pbi_mark_out_notes_',
          ]) ??
          _cleanNote(qrRec?['out_notes']?.toString());
      await _writePrefNotes(
        prefs,
        storageId,
        inNotes: resolvedInNote,
        outNotes: resolvedOutNote,
      );

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
                if (resolvedOutNote != null) 'out_notes': resolvedOutNote,
                'updated_at': now.toIso8601String(),
              })
              .or('bearing_id.eq.$bearingId,bearing_id.eq.$storageId,payload_value.eq.$cleanPayload');
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
                  'in_notes': resolvedInNote,
                  'out_notes': resolvedOutNote,
                  'notes': resolvedOutNote ?? resolvedInNote,
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
        notes: resolvedOutNote ?? resolvedInNote,
        inNotes: resolvedInNote,
        outNotes: resolvedOutNote,
        lifecycleHistory: history,
        rawPayload: cleanPayload,
      );
    } else {
      // =======================================================================
      // ACTION: BEARING IN
      // =======================================================================
      final resolvedInNote = _cleanNote(notes) ??
          _readPrefNotes(prefs, storageId, const [
            'pbi_bearing_in_notes_',
            'pbi_bearing_notes_',
          ]);
      if (resolvedInNote != null) {
        await _writePrefNotes(prefs, storageId, inNotes: resolvedInNote);
      }

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
                if (resolvedInNote != null) 'in_notes': resolvedInNote,
                'updated_at': now.toIso8601String(),
              })
              .or('bearing_id.eq.$bearingId,bearing_id.eq.$storageId,payload_value.eq.$cleanPayload');
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
        notes: resolvedInNote,
        inNotes: resolvedInNote,
        lifecycleHistory: history,
        rawPayload: cleanPayload,
      );
    }
  }

  /// Persist or update notes for a bearing
  static Future<void> saveBearingNotes(String bearingId, String notes, {bool isOut = false}) async {
    final id = _extractRawBearingId(bearingId);
    final clean = notes.trim();
    final prefs = await SharedPreferences.getInstance();
    if (isOut) {
      await _writePrefNotes(prefs, id, outNotes: clean);
      await _syncNotesToSupabase(id, outNotes: clean);
    } else {
      await _writePrefNotes(prefs, id, inNotes: clean);
      await _syncNotesToSupabase(id, inNotes: clean);
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
    final prefs = await SharedPreferences.getInstance();

    // 1. Supabase Query
    if (SupabaseService.isInitialized) {
      try {
        List<dynamic> res;
        try {
          res = await SupabaseService.client
              .from('qr_codes')
              .select('''
                bearing_id,
                model_number,
                first_in_timestamp,
                last_in_timestamp,
                current_lifecycle_state,
                in_notes,
                notes,
                qr_batches (batch_code)
              ''')
              .eq('current_lifecycle_state', 'CURRENTLY_IN')
              .order('last_in_timestamp', ascending: false);
        } catch (_) {
          res = await SupabaseService.client
              .from('qr_codes')
              .select('''
                bearing_id,
                model_number,
                first_in_timestamp,
                last_in_timestamp,
                current_lifecycle_state,
                notes,
                qr_batches (batch_code)
              ''')
              .eq('current_lifecycle_state', 'CURRENTLY_IN')
              .order('last_in_timestamp', ascending: false);
        }

        for (final row in res) {
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

          final inNote = _cleanNote(m['in_notes']?.toString()) ??
              _cleanNote(m['notes']?.toString()) ??
              _readPrefNotes(prefs, bid, const ['pbi_bearing_in_notes_', 'pbi_bearing_notes_']);

          items.add(BearingHistoryItem(
            bearingId: bid,
            modelNumber: rawModel,
            batchCode: batch,
            inTimestamp: inDt,
            notes: inNote,
            inNotes: inNote,
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
          final notes = _readPrefNotes(prefs, id, const ['pbi_bearing_in_notes_', 'pbi_bearing_notes_']);

          items.add(BearingHistoryItem(
            bearingId: id,
            modelNumber: model,
            batchCode: batch,
            inTimestamp: inDt,
            notes: notes,
            inNotes: notes,
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
    final prefs = await SharedPreferences.getInstance();

    // 1. Supabase Query for completed cycles
    if (SupabaseService.isInitialized) {
      try {
        List<dynamic> res;
        try {
          res = await SupabaseService.client
              .from('bearing_installation_cycles')
              .select('''
                id,
                cycle_number,
                in_timestamp,
                out_timestamp,
                operating_duration_seconds,
                notes,
                in_notes,
                out_notes,
                qr_codes (bearing_id, model_number, in_notes, out_notes, notes, qr_batches (batch_code))
              ''')
              .eq('is_cycle_closed', true)
              .order('out_timestamp', ascending: false);
        } catch (_) {
          res = await SupabaseService.client
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
        }

        for (final row in res) {
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
          final note = _cleanNote(m['notes']?.toString());
          final (splitIn, splitOut) = _splitLegacyOutNotes(note);
          final qrInNote = _cleanNote(qr?['in_notes']?.toString());
          final qrOutNote = _cleanNote(qr?['out_notes']?.toString());
          final qrLegacyNote = _cleanNote(qr?['notes']?.toString());

          var inNote = _cleanNote(m['in_notes']?.toString()) ??
              qrInNote ??
              splitIn ??
              _readPrefNotes(prefs, bid, const ['pbi_bearing_in_notes_']);
          var outNote = _cleanNote(m['out_notes']?.toString()) ??
              qrOutNote ??
              splitOut ??
              _readPrefNotes(prefs, bid, const ['pbi_bearing_out_notes_', 'pbi_mark_out_notes_']);

          // Preserve legacy `notes` if in_notes was not backfilled when out_notes replaced notes
          if (inNote == null && outNote != null && note != null && note != outNote) {
            inNote = note;
          }
          if (inNote == null && qrLegacyNote != null && qrLegacyNote != outNote) {
            inNote = qrLegacyNote;
          }
          if (inNote == null) {
            final legacyPref = _readPrefNotes(prefs, bid, const ['pbi_bearing_notes_']);
            if (legacyPref != null && legacyPref != outNote) {
              inNote = legacyPref;
            }
          }

          final key = '$bid-${outDt.millisecondsSinceEpoch}';
          if (!seenCycles.contains(key)) {
            items.add(BearingHistoryItem(
              bearingId: bid,
              modelNumber: modelNum,
              batchCode: batch,
              inTimestamp: inDt,
              outTimestamp: outDt,
              durationSeconds: dur,
              notes: note ?? outNote ?? inNote,
              inNotes: inNote,
              outNotes: outNote,
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
        final histJson = prefs.getString('$_trackHistoryPrefix$id') ??
            prefs.getString('$_trackHistoryPrefix${id.toUpperCase()}');
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
              final rawEntryNote = _cleanNote(em['notes']?.toString());
              final (splitIn, splitOut) = _splitLegacyOutNotes(rawEntryNote);
              final inNote = _cleanNote(em['in_notes']?.toString()) ??
                  splitIn ??
                  _readPrefNotes(prefs, id, const ['pbi_bearing_in_notes_', 'pbi_bearing_notes_']);
              final outNote = _cleanNote(em['out_notes']?.toString()) ??
                  splitOut ??
                  _readPrefNotes(prefs, id, const ['pbi_bearing_out_notes_', 'pbi_mark_out_notes_']);
              final note = rawEntryNote ?? outNote ?? inNote;

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
                  inNotes: inNote,
                  outNotes: outNote,
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
                final inNote = _readPrefNotes(prefs, id, const ['pbi_bearing_in_notes_', 'pbi_bearing_notes_']);
                final outNote = _readPrefNotes(prefs, id, const ['pbi_bearing_out_notes_', 'pbi_mark_out_notes_']);
                items.add(BearingHistoryItem(
                  bearingId: id,
                  modelNumber: model,
                  batchCode: batch,
                  inTimestamp: inDt,
                  outTimestamp: outDt,
                  durationSeconds: outDt.difference(inDt).inSeconds,
                  notes: outNote ?? inNote,
                  inNotes: inNote,
                  outNotes: outNote,
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
