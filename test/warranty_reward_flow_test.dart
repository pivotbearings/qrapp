import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pivot_bearings_app/features/bearing_verification/data/models/bearing_model.dart';
import 'package:pivot_bearings_app/features/bearing_verification/data/repositories/bearing_repository.dart';
import 'package:pivot_bearings_app/features/bearing_verification/data/services/bearing_authentication_service.dart';
import 'package:pivot_bearings_app/features/bearing_verification/domain/models/qr_verification_result.dart';
import 'package:pivot_bearings_app/features/rewards/data/services/reward_service.dart';
import 'package:pivot_bearings_app/features/qr_generation/data/repositories/qr_management_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    BearingRepositoryImpl.resetInMemoryStore();
    RewardService.liveProfileNotifier.value = null;
  });

  group('Warranty & Authentication Instant Reward Credit Verification', () {
    test('BearingAuthenticationService awards points on 1st authentic scan and prevents duplicates', () async {
      final result1 = await BearingAuthenticationService.authenticateBearing('PB-9402-XJ');
      expect(result1.isAuthentic, true);
      expect(result1.rewardClaim, isNotNull);
      expect(result1.rewardClaim!.rewardAwarded, true);
      expect(result1.rewardClaim!.pointsEarned, greaterThan(0));

      // Live notifier reflects updated balance instantaneously
      expect(RewardService.liveProfileNotifier.value?.currentBalancePoints, result1.rewardClaim!.newBalance);

      // Second scan returns alreadyClaimed without crediting duplicate points
      final result2 = await BearingAuthenticationService.authenticateBearing('https://pivotbearings.in/verify/PB-9402-XJ?ref=1');
      expect(result2.isAuthentic, true);
      expect(result2.rewardClaim?.rewardAwarded, false);
      expect(result2.rewardClaim?.alreadyClaimed, true);
      expect(RewardService.liveProfileNotifier.value?.currentBalancePoints, result1.rewardClaim!.newBalance);
    });

    test('Warranty scan (verifyScannedPayload) credits points on scan even without Mark Bearing IN and caches claim', () async {
      const mixedCaseSerial = 'g#PCbs]HVuQj';
      BearingRepositoryImpl.registerInMemoryBearing(
        const BearingModel(
          id: mixedCaseSerial,
          batchCode: 'BATCH-WARR-01',
          modelNumber: 'B1',
          warrantyDurationMonths: 12,
          state: BearingLifecycleState.notActivated,
        ),
      );
      await QrManagementRepository.syncBearingStateChange(
        bearingId: mixedCaseSerial,
        newState: 'NOT_ACTIVATED',
      );

      final repo = BearingRepositoryImpl();
      final verif = await repo.verifyScannedPayload('https://pivotbearingsindia.com/pbi/g%23PCbs%5DHVuQj/?ref=1#frag');

      expect(verif.status, QrVerificationStatus.validNotActivated);
      expect(verif.rewardClaim?.rewardAwarded, true);
      expect(verif.rewardClaim?.pointsEarned, greaterThan(0));

      // Live profile notifier updated immediately
      expect(RewardService.liveProfileNotifier.value?.currentBalancePoints, verif.rewardClaim!.newBalance);

      // Cached claim available instantaneously for InConfirmationScreen
      final cached = RewardService.getRecentClaimForBearing(mixedCaseSerial);
      expect(cached, isNotNull);
      expect(cached!.rewardAwarded, true);

      // Re-scanning or confirming later does not double credit
      final duplicateClaim = await RewardService.claimBearingScanReward(
        rawPayloadOrId: mixedCaseSerial,
        sourceModule: 'WARRANTY_SCAN',
      );
      expect(duplicateClaim.rewardAwarded, false);
      expect(duplicateClaim.alreadyClaimed, true);
    });

    test('Warranty scan works for uncached seed & currentlyIn bearings and awards points once', () async {
      final repo = BearingRepositoryImpl();
      final seedVerif = await repo.verifyScannedPayload('https://pivotbearings.in/verify/PB-9402-XJ/');
      expect(seedVerif.status, QrVerificationStatus.validNotActivated);
      expect(seedVerif.rewardClaim?.rewardAwarded, true);
      final afterSeedBalance = RewardService.liveProfileNotifier.value?.currentBalancePoints ?? 0;
      expect(afterSeedBalance, greaterThan(0));

      BearingRepositoryImpl.registerInMemoryBearing(
        BearingModel(
          id: 'PB-8812-KR',
          batchCode: 'BATCH-WARR-IN',
          modelNumber: 'B1',
          warrantyDurationMonths: 12,
          state: BearingLifecycleState.currentlyIn,
          firstInDate: DateTime.now().subtract(const Duration(days: 5)),
        ),
      );

      final inVerif = await repo.verifyScannedPayload('PB-8812-KR');
      expect(inVerif.status, QrVerificationStatus.validWarrantyActive);
      expect(inVerif.rewardClaim?.rewardAwarded, true);
      expect(RewardService.liveProfileNotifier.value?.currentBalancePoints, greaterThan(afterSeedBalance));
      expect(RewardService.getRecentClaimForBearing('PB-8812-KR')?.rewardAwarded, true);
    });

    test('Invalid QR and Decommissioned bearings never award points', () async {
      final repo = BearingRepositoryImpl();
      final invalidRes = await repo.verifyScannedPayload('FAKE-UNKNOWN-CODE-999');
      expect(invalidRes.isInvalid, true);
      expect(invalidRes.rewardClaim, isNull);
      expect(RewardService.liveProfileNotifier.value, isNull);

      final invalidAuth = await BearingAuthenticationService.authenticateBearing('FAKE-UNKNOWN-CODE-999');
      expect(invalidAuth.isAuthentic, false);
      expect(invalidAuth.rewardClaim, isNull);
    });
  });
}

