import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/widgets/reward_icon.dart';
import '../../domain/models/reward_models.dart';

/// Shared compact banner showing scan reward credit or already-claimed notice.
class ScanRewardBanner extends StatelessWidget {
  final RewardClaimResult claim;

  const ScanRewardBanner({
    super.key,
    required this.claim,
  });

  @override
  Widget build(BuildContext context) {
    if (claim.rewardAwarded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
          border: Border.all(color: AppColors.primary, width: 1.8),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: RewardIcon(color: Colors.white, size: 22),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '1ST SCAN REWARD CLAIMED!',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '+${claim.pointsEarned} Points Credited!',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    'Points added to your Pivot Reward Wallet.',
                    style: TextStyle(
                      color: AppColors.primary.withValues(alpha: 0.75),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (claim.alreadyClaimed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
          border: Border.all(color: Colors.black12, width: 1.2),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.primary.withValues(alpha: 0.7), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'First-scan reward points for this bearing have already been claimed.',
                style: TextStyle(
                  color: AppColors.primary.withValues(alpha: 0.85),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

