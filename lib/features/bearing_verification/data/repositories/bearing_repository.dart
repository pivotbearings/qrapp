import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/app_config.dart';
import '../models/bearing_model.dart';
import '../models/verification_event.dart';
import '../../domain/models/qr_verification_result.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../qr_generation/domain/services/bearing_encryption_key_service.dart';
import '../../../qr_generation/data/repositories/qr_management_repository.dart';
import '../../domain/services/warranty_calculator.dart';
import '../../../rewards/data/services/reward_service.dart';
import '../../../item_master/data/repositories/item_master_repository.dart';

abstract class BearingRepository {
  Future<QrVerificationResult> verifyScannedPayload(String payload);
  Future<BearingModel?> getBearingById(String id);
  Future<BearingModel> markBearingIn(String id, {String? proofImageHash, String? notes, bool skipRemoteRpc = false});
  Future<BearingModel> markBearingOut(String id, {String? proofImageHash, bool skipRemoteRpc = false});
  Future<List<VerificationEvent>> getEventsForBearing(String bearingId);
  Future<List<BearingModel>> getAllBearings({
    String? customerId,
    String? customerEmail,
    String? facilityCode,
  });
}

class BearingRepositoryImpl implements BearingRepository {
  // In-memory dynamic storage (empty until created/registered dynamically)
  static final Map<String, BearingModel> _inMemoryStore = {};
  static final List<VerificationEvent> _eventsStore = [];
  static int _invalidScansCount = 0;
  static int _totalScansCount = 0;

  static Map<String, BearingModel> get inMemoryStore => Map.unmodifiable(_inMemoryStore);
  static List<VerificationEvent> get eventsStore => List.unmodifiable(_eventsStore);
  static int get totalScansCount => _totalScansCount;
  static int get invalidScansCount => _invalidScansCount;

  static void registerInMemoryBearing(BearingModel bearing) {
    _inMemoryStore[bearing.id] = bearing;
    _inMemoryStore[bearing.id.toUpperCase()] = bearing;
    _inMemoryStore[bearing.id.toLowerCase()] = bearing;
  }

  static void resetInMemoryStore() {
    _inMemoryStore.clear();
    _eventsStore.clear();
  }

  /// Authoritative server-side verification using Supabase `verify_bearing_qr` RPC
  @override
  Future<QrVerificationResult> verifyScannedPayload(String payload) async {
    final res = await _verifyScannedPayloadInternal(payload);
    if (res.status == QrVerificationStatus.validNotActivated ||
        res.status == QrVerificationStatus.validWarrantyActive) {
      try {
        final isClaimed = await RewardService.isBearingRewardClaimed(payload);
        if (isClaimed) {
          return res.copyWithReward(const RewardClaimResult(
            rewardAwarded: false,
            alreadyClaimed: true,
            message: 'First-scan reward has already been claimed for this bearing.',
          ));
        }
      } catch (e) {
        debugPrint('Reward check error: $e');
      }
    }
    return res;
  }

  Future<QrVerificationResult> _verifyScannedPayloadInternal(String payload) async {
    _totalScansCount++;
    final cleanPayload = payload.trim();
    if (cleanPayload.isEmpty) {
      _invalidScansCount++;
      return QrVerificationResult.invalid(message: 'Scanned payload is empty.');
    }

    String bearingId = cleanPayload;
    if (bearingId.contains('/pbi/')) {
      final parts = bearingId.split('/pbi/');
      if (parts.length > 1) {
        bearingId = parts[1].split('?').first.split('&').first;
      }
    } else if (bearingId.contains('://')) {
      final uri = Uri.tryParse(bearingId);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        bearingId = uri.pathSegments.last.split('?').first;
      }
    }
    bearingId = bearingId.toUpperCase().trim();

    // Check permanent OUT state from local storage across modules
    final prefs = await SharedPreferences.getInstance();
    final isLocallyPermanentlyOut = prefs.getBool('pbi_bearing_permanently_out_$bearingId') == true ||
        prefs.getString('pbi_track_state_$bearingId') == 'FINAL_OUT' ||
        prefs.getString('pbi_track_state_$bearingId') == 'DECOMMISSIONED' ||
        prefs.getString('pbi_bearing_state_$bearingId') == 'CURRENTLY_OUT';

    if (isLocallyPermanentlyOut) {
      return QrVerificationResult(
        status: QrVerificationStatus.decommissionedOut,
        bearingId: bearingId,
        currentLifecycleState: 'FINAL_OUT',
        canMarkIn: false,
        canMarkOut: false,
        errorMessage: 'This bearing has been permanently decommissioned. Re-installation is strictly prohibited.',
        payloadHash: 'SHA-256: DECOMMISSIONED',
      );
    }

    if (SupabaseService.isInitialized) {
      // Step 1: Prioritize authoritative server-side RPC verify_bearing_qr
      try {
        final res = await SupabaseService.client.rpc(
          'verify_bearing_qr',
          params: {'p_scanned_payload': cleanPayload},
        );
        if (res != null && res is Map) {
          final resMap = Map<String, dynamic>.from(res);
          if (resMap['status'] != 'INVALID' && resMap['status'] != 'NOT_FOUND') {
            await QrManagementRepository.loadFromLocalStorage();
            final localQr = QrManagementRepository.findQrRecord(cleanPayload) ??
                QrManagementRepository.findQrRecord(bearingId);
            final localDur = (localQr?['duration_months'] as num?)?.toInt();
            final parsed = QrVerificationResult.fromJson(resMap);
            final model = (localQr?['model_number'] != null &&
                    localQr!['model_number'].toString().isNotEmpty &&
                    localQr['model_number'].toString() != 'PBI-6204-ZZ')
                ? localQr['model_number'].toString()
                : (parsed.modelNumber != null && parsed.modelNumber != 'PBI-6204-ZZ'
                    ? parsed.modelNumber!
                    : 'B1');
            final item = ItemMasterRepository().findByCode(model) ?? ItemMasterRepository().findByCode('B1');
            final dur = localDur ?? parsed.warrantyDurationMonths ?? item?.defaultWarrantyMonths ?? 12;
            DateTime? expiry = parsed.warrantyExpiryTimestamp;
            if (parsed.firstInTimestamp != null) {
              expiry = WarrantyCalculator.calculateExpiryDate(firstInDate: parsed.firstInTimestamp!, durationMonths: dur);
            }

            final finalResult = QrVerificationResult(
              status: parsed.status,
              bearingId: parsed.bearingId ?? bearingId,
              batchCode: parsed.batchCode ?? 'BATCH-ACTIVE',
              plantLocation: parsed.plantLocation ?? 'Plant 02 — Chakan Industrial Complex',
              modelNumber: model,
              category: parsed.category ?? item?.category ?? 'Ball Bearing',
              productName: parsed.productName ?? item?.itemName ?? 'Bearing 1(Ball Bearing)',
              warrantyPlanTitle: '$dur Months Industrial Warranty',
              warrantyDurationMonths: dur,
              currentLifecycleState: parsed.currentLifecycleState,
              firstInTimestamp: parsed.firstInTimestamp,
              warrantyExpiryTimestamp: expiry,
              isExpired: expiry != null && expiry.isBefore(DateTime.now()),
              canMarkIn: parsed.canMarkIn,
              canMarkOut: parsed.canMarkOut,
              payloadHash: parsed.payloadHash,
            );

            registerInMemoryBearing(BearingModel(
              id: parsed.bearingId ?? bearingId,
              batchCode: parsed.batchCode ?? 'BATCH-ACTIVE',
              modelNumber: model,
              customCategory: parsed.category ?? item?.category ?? 'Ball Bearing',
              productName: parsed.productName ?? item?.itemName ?? 'Bearing 1(Ball Bearing)',
              plantLocation: parsed.plantLocation ?? 'Plant 02 — Chakan Industrial Complex',
              warrantyDurationMonths: dur,
              state: parsed.currentLifecycleState == 'CURRENTLY_IN'
                  ? BearingLifecycleState.currentlyIn
                  : (parsed.currentLifecycleState == 'CURRENTLY_OUT'
                      ? BearingLifecycleState.currentlyOut
                      : BearingLifecycleState.notActivated),
              firstInDate: parsed.firstInTimestamp,
              explicitExpiryDate: expiry,
            ));
            return finalResult;
          }
        }
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('socket') ||
            errStr.contains('failed host lookup') ||
            errStr.contains('clientexception')) {
          return QrVerificationResult.networkUnavailable(
            message: 'Network connection lost. Unable to contact Supabase registry.',
          );
        }
      }

      // Step 2: Direct Supabase query to `qr_codes`
      try {
        Map<String, dynamic>? row;
        try {
          row = await SupabaseService.client
              .from('qr_codes')
              .select('''
                id,
                bearing_id,
                model_number,
                current_lifecycle_state,
                first_in_timestamp,
                warranty_expiry_timestamp,
                is_flagged,
                flag_reason,
                qr_batches (batch_code, plant_location, default_warranty_plan_id, warranty_plans:default_warranty_plan_id(title, duration_months)),
                warranty_plans:assigned_warranty_plan_id (title, duration_months)
              ''')
              .eq('bearing_id', bearingId)
              .limit(1)
              .maybeSingle();
        } catch (_) {}

        if (row == null) {
          try {
            row = await SupabaseService.client
                .from('qr_codes')
                .select('''
                  id,
                  bearing_id,
                  model_number,
                  current_lifecycle_state,
                  first_in_timestamp,
                  warranty_expiry_timestamp,
                  is_flagged,
                  flag_reason,
                  qr_batches (batch_code, plant_location, default_warranty_plan_id, warranty_plans:default_warranty_plan_id(title, duration_months)),
                  warranty_plans:assigned_warranty_plan_id (title, duration_months)
                ''')
                .eq('payload_value', cleanPayload)
                .limit(1)
                .maybeSingle();
          } catch (_) {}
        }

        if (row == null) {
          try {
            row = await SupabaseService.client
                .from('qr_codes')
                .select('''
                  id,
                  bearing_id,
                  model_number,
                  current_lifecycle_state,
                  first_in_timestamp,
                  warranty_expiry_timestamp,
                  is_flagged,
                  flag_reason,
                  qr_batches (batch_code, plant_location, default_warranty_plan_id, warranty_plans:default_warranty_plan_id(title, duration_months)),
                  warranty_plans:assigned_warranty_plan_id (title, duration_months)
                ''')
                .ilike('bearing_id', bearingId)
                .limit(1)
                .maybeSingle();
          } catch (_) {}
        }

        if (row != null) {
          final batch = row['qr_batches'] as Map<String, dynamic>?;
          final plan = row['warranty_plans'] as Map<String, dynamic>?;
          final batchPlan = batch?['warranty_plans'] as Map<String, dynamic>?;
          final state = row['current_lifecycle_state']?.toString() ?? 'NOT_ACTIVATED';
          final isFlagged = row['is_flagged'] == true;
          final isDecommissioned = state == 'CURRENTLY_OUT' ||
              state == 'FINAL_OUT' ||
              state == 'DECOMMISSIONED' ||
              isLocallyPermanentlyOut;

          final firstIn = row['first_in_timestamp'] != null
              ? DateTime.tryParse(row['first_in_timestamp'].toString())
              : null;
          DateTime? expiry = row['warranty_expiry_timestamp'] != null
              ? DateTime.tryParse(row['warranty_expiry_timestamp'].toString())
              : null;
          final isExpired = expiry != null && expiry.isBefore(DateTime.now());

          QrVerificationStatus status;
          if (isFlagged) {
            status = QrVerificationStatus.qrBlocked;
          } else if (isDecommissioned) {
            status = QrVerificationStatus.decommissionedOut;
          } else if (state == 'NOT_ACTIVATED') {
            status = QrVerificationStatus.validNotActivated;
          } else if (isExpired) {
            status = QrVerificationStatus.warrantyExpired;
          } else {
            status = QrVerificationStatus.validWarrantyActive;
          }

          await QrManagementRepository.loadFromLocalStorage();
          final localQr = QrManagementRepository.findQrRecord(bearingId) ??
              QrManagementRepository.findQrRecord(cleanPayload);
          final localDur = (localQr?['duration_months'] as num?)?.toInt();

          var modelNum = (localQr?['model_number'] != null &&
                  localQr!['model_number'].toString().isNotEmpty &&
                  localQr['model_number'] != 'PBI-6204-ZZ')
              ? localQr['model_number'].toString()
              : (row['model_number'] != null && row['model_number'] != 'PBI-6204-ZZ'
                  ? row['model_number'].toString()
                  : 'B1');
          final item = ItemMasterRepository().findByCode(modelNum) ?? ItemMasterRepository().findByCode('B1');
          int dur = localDur ??
              (plan?['duration_months'] as num?)?.toInt() ??
              (batchPlan?['duration_months'] as num?)?.toInt() ??
              item?.defaultWarrantyMonths ?? 12;

          if (firstIn != null && expiry != null && plan == null && batchPlan == null && localDur == null) {
            final diff = (expiry.year - firstIn.year) * 12 + (expiry.month - firstIn.month);
            if (diff > 0) dur = diff;
          }
          if (firstIn != null) {
            expiry = WarrantyCalculator.calculateExpiryDate(firstInDate: firstIn, durationMonths: dur);
          }

          final finalCategory = item?.category ?? 'Ball Bearing';
          final finalProductName = item?.itemName ?? 'Bearing 1(Ball Bearing)';

          return QrVerificationResult(
            status: status,
            bearingId: row['bearing_id'],
            batchCode: batch?['batch_code'] ?? 'BATCH-ACTIVE',
            plantLocation: batch?['plant_location'] ?? 'Plant 02 — Chakan',
            modelNumber: modelNum,
            category: finalCategory,
            productName: finalProductName,
            warrantyPlanTitle: plan?['title'] ?? batchPlan?['title'] ?? '$dur Months Industrial Warranty',
            warrantyDurationMonths: dur,
            currentLifecycleState: isDecommissioned ? 'FINAL_OUT' : state,
            firstInTimestamp: firstIn,
            warrantyExpiryTimestamp: expiry,
            isExpired: isExpired,
            canMarkIn: state != 'CURRENTLY_IN' && !isDecommissioned,
            canMarkOut: state == 'CURRENTLY_IN' && !isDecommissioned,
            payloadHash: 'SHA-256: VALID',
          );
        }
      } catch (e) {
        // Direct query encountered an error, proceed to fallback
      }
    }

    if (_inMemoryStore.isEmpty) {
      await QrManagementRepository.loadFromLocalStorage();
    }
    return _mockVerifyPayload(cleanPayload);
  }

  QrVerificationResult _mockVerifyPayload(String rawPayload) {
    String bearingId = rawPayload;
    if (bearingId.contains('/pbi/')) {
      final parts = bearingId.split('/pbi/');
      if (parts.length > 1) {
        bearingId = parts[1].split('?').first.split('&').first;
      }
    } else if (bearingId.contains('://')) {
      final uri = Uri.tryParse(bearingId);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        bearingId = uri.pathSegments.last.split('?').first;
      }
    }
    bearingId = bearingId.toUpperCase().trim();

    // Check cryptographic key or serial format validation
    if (!BearingEncryptionKeyService.isValidKeyOrId(bearingId)) {
      return QrVerificationResult.invalid(
        id: bearingId,
        message: 'Malformed or unverified identifier. Format must be an authentic cryptographic key or registered serial.',
      );
    }

    var bearing = _inMemoryStore[bearingId] ??
        _inMemoryStore[bearingId.toUpperCase()] ??
        _inMemoryStore[bearingId.toLowerCase()] ??
        _inMemoryStore[rawPayload] ??
        _inMemoryStore[rawPayload.toUpperCase()] ??
        _inMemoryStore[rawPayload.toLowerCase()];

    if (bearing == null) {
      final qrRec = QrManagementRepository.findQrRecord(bearingId) ??
          QrManagementRepository.findQrRecord(rawPayload);
      if (qrRec != null) {
        final bId = qrRec['bearing_id']?.toString() ?? bearingId;
        final model = qrRec['model_number']?.toString() ?? 'B1';
        final dur = (qrRec['duration_months'] as num?)?.toInt() ?? 12;
        final batch = qrRec['batch_code']?.toString() ?? 'BATCH-ACTIVE';
        final plant = qrRec['plant_location']?.toString() ?? 'Plant 02 — Chakan Industrial Complex';
        final item = ItemMasterRepository().findByCode(model);
        final registered = BearingModel(
          id: bId,
          batchCode: batch,
          modelNumber: model,
          customCategory: qrRec['category']?.toString() ?? item?.category ?? 'Ball Bearing',
          productName: qrRec['product_name']?.toString() ?? item?.itemName ?? 'Bearing 1(Ball Bearing)',
          plantLocation: plant,
          warrantyDurationMonths: dur,
          state: BearingLifecycleState.notActivated,
        );
        registerInMemoryBearing(registered);
        bearing = registered;
      } else {
        return QrVerificationResult.invalid(
          id: bearingId,
          message: 'Cryptographic identifier not registered with Pivot Bearings India.',
        );
      }
    }

    if (bearing.state == BearingLifecycleState.notActivated) {
      return QrVerificationResult(
        status: QrVerificationStatus.validNotActivated,
        bearingId: bearingId,
        batchCode: bearing.batchCode,
        plantLocation: bearing.plantLocation,
        modelNumber: bearing.modelNumber,
        warrantyPlanTitle: '${bearing.warrantyDurationMonths} Months Heavy Duty',
        warrantyDurationMonths: bearing.warrantyDurationMonths,
        currentLifecycleState: 'NOT_ACTIVATED',
        canMarkIn: true,
        canMarkOut: false,
        payloadHash: 'SHA-256: 4F92E389B01A9402',
      );
    }

    final isExpired = bearing.isWarrantyExpired;
    final isCurrentlyIn = bearing.state == BearingLifecycleState.currentlyIn;
    final isCurrentlyOut = bearing.state == BearingLifecycleState.currentlyOut;

    if (isCurrentlyOut) {
      return QrVerificationResult(
        status: QrVerificationStatus.decommissionedOut,
        bearingId: bearingId,
        batchCode: bearing.batchCode,
        plantLocation: bearing.plantLocation,
        modelNumber: bearing.modelNumber,
        warrantyPlanTitle: '${bearing.warrantyDurationMonths} Months Heavy Duty',
        warrantyDurationMonths: bearing.warrantyDurationMonths,
        currentLifecycleState: 'CURRENTLY_OUT',
        firstInTimestamp: bearing.firstInDate,
        warrantyExpiryTimestamp: bearing.warrantyExpiryDate,
        isExpired: isExpired,
        canMarkIn: false,
        canMarkOut: false,
        errorMessage: 'Bearing completed operational lifecycle and is permanently decommissioned. Re-installation is strictly prohibited.',
        payloadHash: 'SHA-256: 9C82A109D45E8812',
      );
    }

    return QrVerificationResult(
      status: isExpired ? QrVerificationStatus.warrantyExpired : QrVerificationStatus.validWarrantyActive,
      bearingId: bearingId,
      batchCode: bearing.batchCode,
      plantLocation: bearing.plantLocation,
      modelNumber: bearing.modelNumber,
      warrantyPlanTitle: '${bearing.warrantyDurationMonths} Months Heavy Duty',
      warrantyDurationMonths: bearing.warrantyDurationMonths,
      currentLifecycleState: isCurrentlyIn ? 'CURRENTLY_IN' : 'CURRENTLY_OUT',
      firstInTimestamp: bearing.firstInDate,
      warrantyExpiryTimestamp: bearing.warrantyExpiryDate,
      isExpired: isExpired,
      canMarkIn: false,
      canMarkOut: isCurrentlyIn,
      payloadHash: 'SHA-256: 9C82A109D45E8812',
    );
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
    return id.trim();
  }

  @override
  Future<BearingModel?> getBearingById(String id) async {
    final rawId = id.trim();
    if (rawId.isEmpty) return null;
    final cleanId = _extractBearingId(rawId);
    final upperId = cleanId.toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    final isLocallyOut = prefs.getBool('pbi_bearing_permanently_out_$cleanId') == true ||
        prefs.getBool('pbi_bearing_permanently_out_$upperId') == true ||
        prefs.getString('pbi_track_state_$cleanId') == 'FINAL_OUT' ||
        prefs.getString('pbi_track_state_$upperId') == 'FINAL_OUT' ||
        prefs.getString('pbi_bearing_state_$cleanId') == 'CURRENTLY_OUT' ||
        prefs.getString('pbi_bearing_state_$upperId') == 'CURRENTLY_OUT';

    // 1. Authoritative Server RPC: get_bearing_lifecycle_summary
    if (SupabaseService.isInitialized) {
      try {
        final rpcRes = await SupabaseService.client.rpc('get_bearing_lifecycle_summary', params: {
          'p_scanned_payload': rawId,
        });
        if (rpcRes != null && rpcRes is Map) {
          final summary = Map<String, dynamic>.from(rpcRes);
          if (summary['success'] == true) {
            final dur = (summary['warranty_duration_months'] as num).toInt();
            final firstIn = summary['first_in_timestamp'] != null
                ? DateTime.tryParse(summary['first_in_timestamp'].toString())
                : null;
            final lastOut = summary['last_out_timestamp'] != null
                ? DateTime.tryParse(summary['last_out_timestamp'].toString())
                : null;
            DateTime? expiry = summary['warranty_expiry_timestamp'] != null
                ? DateTime.tryParse(summary['warranty_expiry_timestamp'].toString())
                : null;
            if (firstIn != null && expiry == null) {
              expiry = WarrantyCalculator.calculateExpiryDate(firstInDate: firstIn, durationMonths: dur);
            }

            BearingLifecycleState state = BearingLifecycleState.notActivated;
            final stateStr = summary['current_lifecycle_state']?.toString();
            if (isLocallyOut || stateStr == 'CURRENTLY_OUT' || stateStr == 'FINAL_OUT' || stateStr == 'DECOMMISSIONED') {
              state = BearingLifecycleState.currentlyOut;
            } else if (stateStr == 'CURRENTLY_IN' ||
                prefs.getString('pbi_track_state_$cleanId') == 'IN' ||
                prefs.getString('pbi_bearing_state_$cleanId') == 'CURRENTLY_IN') {
              state = BearingLifecycleState.currentlyIn;
            }

            final resBearing = BearingModel(
              id: summary['bearing_id']?.toString() ?? cleanId,
              batchCode: summary['batch_code']?.toString() ?? 'BATCH-ACTIVE',
              modelNumber: summary['model_number']?.toString() ?? 'B1',
              customCategory: summary['category']?.toString() ?? 'Ball Bearing',
              productName: summary['product_name']?.toString() ?? 'Bearing 1(Ball Bearing)',
              plantLocation: summary['plant_location']?.toString() ?? 'Plant 02 — Chakan Industrial Complex',
              warrantyDurationMonths: dur,
              state: state,
              firstInDate: firstIn,
              lastInDate: firstIn,
              lastOutDate: lastOut,
              explicitExpiryDate: expiry,
            );
            registerInMemoryBearing(resBearing);
            return resBearing;
          }
        }
      } catch (_) {}
    }

    // 2. Direct Supabase Query with exact joined warranty plan
    if (SupabaseService.isInitialized) {
      try {
        Map<String, dynamic>? response;
        try {
          response = await SupabaseService.client
              .from('qr_codes')
              .select('''
                id,
                bearing_id,
                model_number,
                warranty_duration_months,
                current_lifecycle_state,
                first_in_timestamp,
                last_out_timestamp,
                warranty_expiry_timestamp,
                is_flagged,
                flag_reason,
                qr_batches (batch_code, plant_location, default_warranty_plan_id, warranty_plans:default_warranty_plan_id(title, duration_months)),
                warranty_plans:assigned_warranty_plan_id (title, duration_months)
              ''')
              .eq('bearing_id', cleanId)
              .maybeSingle();
        } catch (_) {}

        if (response == null) {
          try {
            response = await SupabaseService.client
                .from('qr_codes')
                .select('''
                  id,
                  bearing_id,
                  model_number,
                  warranty_duration_months,
                  current_lifecycle_state,
                  first_in_timestamp,
                  last_out_timestamp,
                  warranty_expiry_timestamp,
                  is_flagged,
                  flag_reason,
                  qr_batches (batch_code, plant_location, default_warranty_plan_id, warranty_plans:default_warranty_plan_id(title, duration_months)),
                  warranty_plans:assigned_warranty_plan_id (title, duration_months)
                ''')
                .ilike('bearing_id', cleanId)
                .maybeSingle();
          } catch (_) {}
        }

        if (response != null) {
          final batch = response['qr_batches'] as Map<String, dynamic>?;
          final plan = response['warranty_plans'] as Map<String, dynamic>?;
          final batchPlan = batch?['warranty_plans'] as Map<String, dynamic>?;

          await QrManagementRepository.loadFromLocalStorage();
          final localQr = QrManagementRepository.findQrRecord(cleanId) ??
              QrManagementRepository.findQrRecord(rawId);
          final localDur = (localQr?['duration_months'] as num?)?.toInt();

          final dur = (response['warranty_duration_months'] as num?)?.toInt() ??
              (plan?['duration_months'] as num?)?.toInt() ??
              localDur ??
              (batchPlan?['duration_months'] as num?)?.toInt();

          if (dur != null) {
            BearingLifecycleState state = BearingLifecycleState.notActivated;
            final dbState = response['current_lifecycle_state']?.toString();
            if (isLocallyOut || dbState == 'CURRENTLY_OUT' || dbState == 'FINAL_OUT' || dbState == 'DECOMMISSIONED') {
              state = BearingLifecycleState.currentlyOut;
            } else if (dbState == 'CURRENTLY_IN' ||
                prefs.getString('pbi_track_state_$cleanId') == 'IN' ||
                prefs.getString('pbi_bearing_state_$cleanId') == 'CURRENTLY_IN') {
              state = BearingLifecycleState.currentlyIn;
            }

            final firstIn = response['first_in_timestamp'] != null
                ? DateTime.tryParse(response['first_in_timestamp'].toString())
                : (prefs.getString('pbi_track_in_time_$cleanId') != null
                    ? DateTime.tryParse(prefs.getString('pbi_track_in_time_$cleanId')!)
                    : null);
            final lastOut = response['last_out_timestamp'] != null
                ? DateTime.tryParse(response['last_out_timestamp'].toString())
                : (prefs.getString('pbi_track_out_time_$cleanId') != null
                    ? DateTime.tryParse(prefs.getString('pbi_track_out_time_$cleanId')!)
                    : null);
            DateTime? expiry = response['warranty_expiry_timestamp'] != null
                ? DateTime.tryParse(response['warranty_expiry_timestamp'].toString())
                : null;
            if (firstIn != null && expiry == null) {
              expiry = WarrantyCalculator.calculateExpiryDate(firstInDate: firstIn, durationMonths: dur);
            }

            final resBearing = BearingModel(
              id: response['bearing_id']?.toString() ?? cleanId,
              batchCode: batch?['batch_code']?.toString() ?? 'BATCH-ACTIVE',
              modelNumber: response['model_number']?.toString() ?? 'B1',
              customCategory: 'Ball Bearing',
              productName: 'Bearing 1(Ball Bearing)',
              plantLocation: batch?['plant_location']?.toString() ?? 'Plant 02 — Chakan Industrial Complex',
              warrantyDurationMonths: dur,
              state: state,
              firstInDate: firstIn,
              lastInDate: firstIn,
              lastOutDate: lastOut,
              explicitExpiryDate: expiry,
            );
            registerInMemoryBearing(resBearing);
            return resBearing;
          }
        }
      } catch (_) {}
    }

    // 3. Local Storage Resolution (Deterministic QR registry)
    await QrManagementRepository.loadFromLocalStorage();
    final qrRec = QrManagementRepository.findQrRecord(cleanId) ??
        QrManagementRepository.findQrRecord(rawId);
    if (qrRec != null) {
      final dur = (qrRec['duration_months'] as num?)?.toInt();
      if (dur != null) {
        final firstIn = qrRec['first_in_timestamp'] != null
            ? DateTime.tryParse(qrRec['first_in_timestamp'].toString())
            : (prefs.getString('pbi_track_in_time_$cleanId') != null
                ? DateTime.tryParse(prefs.getString('pbi_track_in_time_$cleanId')!)
                : null);
        final lastOut = qrRec['last_out_timestamp'] != null
            ? DateTime.tryParse(qrRec['last_out_timestamp'].toString())
            : (prefs.getString('pbi_track_out_time_$cleanId') != null
                ? DateTime.tryParse(prefs.getString('pbi_track_out_time_$cleanId')!)
                : null);
        final expiry = firstIn != null
            ? WarrantyCalculator.calculateExpiryDate(firstInDate: firstIn, durationMonths: dur)
            : null;

        BearingLifecycleState state = BearingLifecycleState.notActivated;
        final dbState = qrRec['current_lifecycle_state']?.toString();
        if (isLocallyOut || dbState == 'CURRENTLY_OUT' || dbState == 'FINAL_OUT' || dbState == 'DECOMMISSIONED') {
          state = BearingLifecycleState.currentlyOut;
        } else if (dbState == 'CURRENTLY_IN' ||
            prefs.getString('pbi_track_state_$cleanId') == 'IN' ||
            prefs.getString('pbi_bearing_state_$cleanId') == 'CURRENTLY_IN') {
          state = BearingLifecycleState.currentlyIn;
        }

        final resolvedBearing = BearingModel(
          id: qrRec['bearing_id']?.toString() ?? cleanId,
          batchCode: qrRec['batch_code']?.toString() ?? 'BATCH-ACTIVE',
          modelNumber: qrRec['model_number']?.toString() ?? 'B1',
          customCategory: 'Ball Bearing',
          productName: 'Bearing 1(Ball Bearing)',
          plantLocation: qrRec['plant_location']?.toString() ?? 'Plant 02 — Chakan Industrial Complex',
          warrantyDurationMonths: dur,
          state: state,
          firstInDate: firstIn,
          lastInDate: firstIn,
          lastOutDate: lastOut,
          explicitExpiryDate: expiry,
        );
        registerInMemoryBearing(resolvedBearing);
        return resolvedBearing;
      }
    }

    // 4. In-Memory Store
    final cached = _inMemoryStore[cleanId] ??
        _inMemoryStore[rawId] ??
        _inMemoryStore[upperId];
    if (cached != null) {
      if (isLocallyOut && cached.state != BearingLifecycleState.currentlyOut) {
        final outDate = DateTime.tryParse(prefs.getString('pbi_track_out_time_$cleanId') ?? '') ?? DateTime.now();
        return BearingModel(
          id: cached.id,
          batchCode: cached.batchCode,
          modelNumber: cached.modelNumber,
          customCategory: cached.customCategory,
          productName: cached.productName,
          plantLocation: cached.plantLocation,
          warrantyDurationMonths: cached.warrantyDurationMonths,
          state: BearingLifecycleState.currentlyOut,
          firstInDate: cached.firstInDate,
          lastInDate: cached.lastInDate,
          lastOutDate: outDate,
          assignedCustomerId: cached.assignedCustomerId,
          assignedCustomerEmail: cached.assignedCustomerEmail,
          customerName: cached.customerName,
          explicitExpiryDate: cached.warrantyExpiryDate,
        );
      }
      return cached;
    }

    return null;
  }

  @override
  Future<BearingModel> markBearingIn(
    String id, {
    String? proofImageHash,
    String? notes,
    bool skipRemoteRpc = false,
  }) async {
    final cleanId = _extractBearingId(id);
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    final isPermanentlyOut = prefs.getBool('pbi_bearing_permanently_out_$cleanId') == true ||
        prefs.getString('pbi_track_state_$cleanId') == 'FINAL_OUT' ||
        prefs.getString('pbi_bearing_state_$cleanId') == 'CURRENTLY_OUT';

    if (isPermanentlyOut) {
      throw StateError('Bearing $cleanId has already been marked OUT and is permanently decommissioned. Re-installation is strictly prohibited.');
    }

    BearingModel? existing = await getBearingById(cleanId);

    final upperId = cleanId.toUpperCase();
    // ========================================================================
    // AUTO-MODE ENFORCEMENT:
    // If bearing is ALREADY currently marked IN, automatically toggle to mark OUT!
    // No duplicate IN entries can ever exist!
    // ========================================================================
    if (existing?.state == BearingLifecycleState.currentlyIn ||
        prefs.getString('pbi_track_state_$cleanId') == 'IN' ||
        prefs.getString('pbi_track_state_$upperId') == 'IN' ||
        prefs.getString('pbi_bearing_state_$cleanId') == 'CURRENTLY_IN' ||
        prefs.getString('pbi_bearing_state_$upperId') == 'CURRENTLY_IN') {
      debugPrint('Bearing $cleanId is ALREADY marked IN. Auto-toggling to mark OUT.');
      return await markBearingOut(id, proofImageHash: proofImageHash, skipRemoteRpc: skipRemoteRpc);
    }
    if (existing == null) {
      await QrManagementRepository.loadFromLocalStorage();
      final qrRec = QrManagementRepository.findQrRecord(cleanId) ??
          QrManagementRepository.findQrRecord(upperId);
      final model = qrRec?['model_number']?.toString() ?? 'B1';
      final batch = qrRec?['batch_code']?.toString() ?? 'BATCH-ACTIVE';
      final plant = qrRec?['plant_location']?.toString() ?? 'Plant 02 — Chakan Industrial Complex';
      final dur = (qrRec?['duration_months'] as num?)?.toInt() ?? 12;
      existing = BearingModel(
        id: cleanId,
        batchCode: batch,
        modelNumber: model,
        plantLocation: plant,
        warrantyDurationMonths: dur,
        state: BearingLifecycleState.notActivated,
      );
    }

    final dur = existing.warrantyDurationMonths;
    final inTime = existing.firstInDate ?? now;
    final calculatedExpiry = WarrantyCalculator.calculateExpiryDate(
      firstInDate: inTime,
      durationMonths: dur,
    );

    // 1. Authoritative Supabase confirmation with resilient fallback
    if (SupabaseService.isInitialized) {
      if (!skipRemoteRpc) {
        try {
          await SupabaseService.confirmBearingIn(
            bearingId: cleanId,
            notes: notes ?? 'Marked IN via Pivot Bearings App',
          );
        } catch (e) {
          debugPrint('Supabase confirm_bearing_in error, executing direct table sync fallback: $e');
        }
      }
      try {
        await SupabaseService.client
            .from('qr_codes')
            .update({
              'current_lifecycle_state': 'CURRENTLY_IN',
              'first_in_timestamp': inTime.toIso8601String(),
              'last_in_timestamp': now.toIso8601String(),
              'warranty_expiry_timestamp': calculatedExpiry.toIso8601String(),
              'warranty_duration_months': dur,
              'assigned_customer_id': AuthController.instance.userId,
              'updated_at': now.toIso8601String(),
            })
            .or('bearing_id.eq.$cleanId,bearing_id.ilike.$cleanId,payload_value.eq.$cleanId');
      } catch (_) {}
    }

    // 2. Comprehensive SharedPreferences synchronization across all modules
    await prefs.setString('pbi_track_state_$cleanId', 'IN');
    await prefs.setString('pbi_track_in_time_$cleanId', now.toIso8601String());
    await prefs.setString('pbi_bearing_state_$cleanId', 'CURRENTLY_IN');

    final trackedList = prefs.getStringList('pbi_tracked_bearings_list') ?? [];
    if (!trackedList.contains(cleanId)) {
      trackedList.insert(0, cleanId);
      await prefs.setStringList('pbi_tracked_bearings_list', trackedList);
    }

    final updated = BearingModel(
      id: existing.id,
      batchCode: existing.batchCode,
      warrantyDurationMonths: existing.warrantyDurationMonths,
      state: BearingLifecycleState.currentlyIn,
      firstInDate: existing.firstInDate ?? now,
      lastInDate: now,
      lastOutDate: null,
      customerName: existing.customerName ?? AuthController.instance.userName,
      assignedCustomerId: existing.assignedCustomerId ?? AuthController.instance.userId,
      assignedCustomerEmail: existing.assignedCustomerEmail ?? AuthController.instance.userEmail,
      plantLocation: existing.plantLocation,
      modelNumber: existing.modelNumber,
    );

    registerInMemoryBearing(updated);
    _eventsStore.add(
      VerificationEvent(
        id: 'evt-${DateTime.now().millisecondsSinceEpoch}',
        bearingId: cleanId,
        eventType: VerificationEventType.inEvent,
        serverTimestamp: now,
        operatorId: AuthController.instance.userName ?? 'Field Engineer (Operator)',
        proofImageHash: proofImageHash,
      ),
    );

    await QrManagementRepository.syncBearingStateChange(
      bearingId: cleanId,
      newState: 'CURRENTLY_IN',
      inTimestamp: updated.firstInDate,
      expiryTimestamp: updated.warrantyExpiryDate,
    );

    return updated;
  }

  @override
  Future<BearingModel> markBearingOut(
    String id, {
    String? proofImageHash,
    bool skipRemoteRpc = false,
  }) async {
    final cleanId = _extractBearingId(id);
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    // 1. Fetch or gracefully auto-resolve bearing record
    BearingModel? existing = await getBearingById(cleanId);
    if (existing == null) {
      await QrManagementRepository.loadFromLocalStorage();
      final qrRec = QrManagementRepository.findQrRecord(cleanId);
      final model = qrRec?['model_number']?.toString() ?? 'B1';
      final batch = qrRec?['batch_code']?.toString() ?? 'BATCH-ACTIVE';
      final plant = qrRec?['plant_location']?.toString() ?? 'Plant 02 — Chakan Industrial Complex';
      final dur = (qrRec?['duration_months'] as num?)?.toInt() ?? 12;
      existing = BearingModel(
        id: cleanId,
        batchCode: batch,
        modelNumber: model,
        plantLocation: plant,
        warrantyDurationMonths: dur,
        state: BearingLifecycleState.currentlyIn,
        firstInDate: now.subtract(const Duration(hours: 1)),
        lastInDate: now.subtract(const Duration(hours: 1)),
      );
    }

    // 2. Seamless idempotent behavior: if already marked OUT, return decommissioned model
    if (existing.state == BearingLifecycleState.currentlyOut) {
      final outDate = existing.lastOutDate ?? now;
      await prefs.setBool('pbi_bearing_permanently_out_$cleanId', true);
      await prefs.setString('pbi_track_state_$cleanId', 'FINAL_OUT');
      await prefs.setString('pbi_track_out_time_$cleanId', outDate.toIso8601String());
      await prefs.setString('pbi_bearing_state_$cleanId', 'CURRENTLY_OUT');
      await QrManagementRepository.syncBearingStateChange(
        bearingId: cleanId,
        newState: 'CURRENTLY_OUT',
        inTimestamp: existing.firstInDate,
        outTimestamp: outDate,
      );
      return existing;
    }

    // 3. Authoritative Supabase confirmation with resilient direct table fallback
    if (SupabaseService.isInitialized) {
      if (!skipRemoteRpc) {
        try {
          await SupabaseService.confirmBearingOut(
            bearingId: cleanId,
            notes: 'Marked OUT via Pivot Bearings App',
          );
        } catch (e) {
          debugPrint('Supabase confirm_bearing_out error, executing direct table fallback: $e');
        }
      }
      try {
        await SupabaseService.client
            .from('qr_codes')
            .update({
              'current_lifecycle_state': 'CURRENTLY_OUT',
              'last_out_timestamp': now.toIso8601String(),
              'assigned_customer_id': AuthController.instance.userId,
              'updated_at': now.toIso8601String(),
            })
            .or('bearing_id.eq.$cleanId,bearing_id.ilike.$cleanId,payload_value.eq.$cleanId');
      } catch (_) {}
    }

    // 4. Update persistent state across all storage layers
    final inTime = existing.firstInDate ??
        existing.lastInDate ??
        (DateTime.tryParse(prefs.getString('pbi_track_in_time_$cleanId') ?? '') ?? now.subtract(const Duration(hours: 1)));

    await prefs.setBool('pbi_bearing_permanently_out_$cleanId', true);
    await prefs.setString('pbi_track_state_$cleanId', 'FINAL_OUT');
    await prefs.setString('pbi_track_out_time_$cleanId', now.toIso8601String());
    await prefs.setString('pbi_bearing_state_$cleanId', 'CURRENTLY_OUT');

    final trackedList = prefs.getStringList('pbi_tracked_bearings_list') ?? [];
    if (!trackedList.contains(cleanId)) {
      trackedList.insert(0, cleanId);
      await prefs.setStringList('pbi_tracked_bearings_list', trackedList);
    }

    // Sync TrackBearingScreen history
    final historyKey = 'pbi_track_history_$cleanId';
    List<dynamic> historyList = [];
    final histStr = prefs.getString(historyKey);
    if (histStr != null) {
      try {
        historyList = jsonDecode(histStr) as List<dynamic>;
      } catch (_) {}
    }
    final durSec = now.difference(inTime).inSeconds;
    historyList.insert(0, {
      'cycle_number': historyList.length + 1,
      'in_timestamp': inTime.toIso8601String(),
      'out_timestamp': now.toIso8601String(),
      'duration_seconds': durSec > 0 ? durSec : 1,
    });
    await prefs.setString(historyKey, jsonEncode(historyList));

    final updated = BearingModel(
      id: existing.id,
      batchCode: existing.batchCode,
      warrantyDurationMonths: existing.warrantyDurationMonths,
      state: BearingLifecycleState.currentlyOut,
      firstInDate: inTime,
      lastInDate: inTime,
      lastOutDate: now,
      customerName: existing.customerName ?? AuthController.instance.userName,
      assignedCustomerId: existing.assignedCustomerId ?? AuthController.instance.userId,
      assignedCustomerEmail: existing.assignedCustomerEmail ?? AuthController.instance.userEmail,
      plantLocation: existing.plantLocation,
      modelNumber: existing.modelNumber,
      explicitExpiryDate: existing.warrantyExpiryDate,
    );

    registerInMemoryBearing(updated);
    _eventsStore.add(
      VerificationEvent(
        id: 'evt-${DateTime.now().millisecondsSinceEpoch}',
        bearingId: cleanId,
        eventType: VerificationEventType.outEvent,
        serverTimestamp: now,
        operatorId: AuthController.instance.userName ?? 'Field Engineer (Operator)',
        proofImageHash: proofImageHash,
      ),
    );

    await QrManagementRepository.syncBearingStateChange(
      bearingId: cleanId,
      newState: 'CURRENTLY_OUT',
      inTimestamp: inTime,
      outTimestamp: now,
    );

    return updated;
  }

  @override
  Future<List<VerificationEvent>> getEventsForBearing(String bearingId) async {
    return _eventsStore.where((e) => e.bearingId == bearingId).toList();
  }

  @override
  Future<List<BearingModel>> getAllBearings({
    String? customerId,
    String? customerEmail,
    String? facilityCode,
  }) async {
    final auth = AuthController.instance;
    final isCustomerSession = !auth.isAdmin;
    final effectiveCustomerId = customerId ?? (isCustomerSession ? auth.userId : null);
    final effectiveCustomerEmail = customerEmail ?? (isCustomerSession ? auth.userEmail : null);

    if (SupabaseService.isInitialized) {
      try {
        var query = SupabaseService.client
            .from('qr_codes')
            .select('''
              bearing_id,
              model_number,
              current_lifecycle_state,
              first_in_timestamp,
              last_out_timestamp,
              warranty_expiry_timestamp,
              assigned_customer_id,
              qr_batches (batch_code, plant_location),
              warranty_plans:assigned_warranty_plan_id (title, duration_months)
            ''');

        if (effectiveCustomerId != null && effectiveCustomerId.isNotEmpty) {
          query = query.eq('assigned_customer_id', effectiveCustomerId);
        }

        final response = await query.order('created_at', ascending: false);

        final list = (response as List).map((row) {
          final m = Map<String, dynamic>.from(row as Map);
          final batch = m['qr_batches'] as Map<String, dynamic>?;
          final plan = m['warranty_plans'] as Map<String, dynamic>?;

          BearingLifecycleState state = BearingLifecycleState.notActivated;
          switch (m['current_lifecycle_state']) {
            case 'CURRENTLY_IN':
              state = BearingLifecycleState.currentlyIn;
              break;
            case 'CURRENTLY_OUT':
              state = BearingLifecycleState.currentlyOut;
              break;
            default:
              state = BearingLifecycleState.notActivated;
          }

          final firstIn = m['first_in_timestamp'] != null ? DateTime.tryParse(m['first_in_timestamp'].toString()) : null;
          final lastOut = m['last_out_timestamp'] != null ? DateTime.tryParse(m['last_out_timestamp'].toString()) : null;
          final expiry = m['warranty_expiry_timestamp'] != null ? DateTime.tryParse(m['warranty_expiry_timestamp'].toString()) : null;

          int dur = 6;
          if (plan != null && plan['duration_months'] is num) {
            dur = (plan['duration_months'] as num).toInt();
          } else if (firstIn != null && expiry != null) {
            final diff = (expiry.year - firstIn.year) * 12 + (expiry.month - firstIn.month);
            if (diff > 0) dur = diff;
          }

          return BearingModel(
            id: m['bearing_id'],
            batchCode: batch?['batch_code'] ?? 'UNKNOWN',
            modelNumber: m['model_number'] ?? 'PBI-MODEL',
            plantLocation: batch?['plant_location'] ?? 'Plant 01',
            warrantyDurationMonths: dur,
            state: state,
            assignedCustomerId: m['assigned_customer_id']?.toString(),
            firstInDate: firstIn,
            lastInDate: firstIn,
            lastOutDate: lastOut,
            explicitExpiryDate: expiry,
          );
        }).toList();

        // Merge locally tracked bearings if not already included
        final prefs = await SharedPreferences.getInstance();
        final localTracked = prefs.getStringList('pbi_tracked_bearings_list') ?? [];
        for (final tid in localTracked) {
          if (!list.any((b) => b.id.toUpperCase() == tid.toUpperCase())) {
            final localModel = await getBearingById(tid);
            if (localModel != null) {
              list.add(localModel);
            }
          }
        }

        return list;
      } catch (e) {
        if (AppConfig.isProduction) rethrow;
      }
    }

    final all = _inMemoryStore.values.toList();
    if (isCustomerSession) {
      // For authenticated customer sessions, only show bearings explicitly assigned to their ID or email.
      // If none match, strictly return an empty list (0 bearings).
      return all.where((b) {
        final matchId = effectiveCustomerId != null && b.assignedCustomerId == effectiveCustomerId;
        final matchEmail = effectiveCustomerEmail != null &&
            (b.assignedCustomerEmail?.toLowerCase() == effectiveCustomerEmail.toLowerCase() ||
             b.customerName?.toLowerCase() == effectiveCustomerEmail.toLowerCase());
        return matchId || matchEmail;
      }).toList();
    }

    if (effectiveCustomerId != null || effectiveCustomerEmail != null) {
      return all.where((b) {
        final matchId = effectiveCustomerId != null && b.assignedCustomerId == effectiveCustomerId;
        final matchEmail = effectiveCustomerEmail != null &&
            (b.assignedCustomerEmail?.toLowerCase() == effectiveCustomerEmail.toLowerCase() ||
             b.customerName?.toLowerCase() == effectiveCustomerEmail.toLowerCase());
        return matchId || matchEmail;
      }).toList();
    }

    return all;
  }
}
