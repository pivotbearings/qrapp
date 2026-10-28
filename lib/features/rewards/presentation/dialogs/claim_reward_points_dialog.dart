import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../data/services/reward_service.dart';
import '../../domain/models/reward_models.dart';

/// Modal dialog for claiming bearing reward points with mandatory supplier details.
class ClaimRewardPointsDialog extends StatefulWidget {
  final String bearingId;
  final String sourceModule;

  const ClaimRewardPointsDialog({
    super.key,
    required this.bearingId,
    this.sourceModule = 'AUTHENTICATE_BEARING',
  });

  static Future<RewardClaimResult?> show(
    BuildContext context, {
    required String bearingId,
    String sourceModule = 'AUTHENTICATE_BEARING',
  }) {
    return showDialog<RewardClaimResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ClaimRewardPointsDialog(
        bearingId: bearingId,
        sourceModule: sourceModule,
      ),
    );
  }

  @override
  State<ClaimRewardPointsDialog> createState() => _ClaimRewardPointsDialogState();
}

class _ClaimRewardPointsDialogState extends State<ClaimRewardPointsDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _supplierNameCtrl = TextEditingController();
  final TextEditingController _supplierContactCtrl = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _supplierNameCtrl.dispose();
    _supplierContactCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitClaim() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _supplierNameCtrl.text.trim();
    final contact = _supplierContactCtrl.text.trim();

    setState(() => _isSubmitting = true);

    try {
      final result = await RewardService.claimBearingScanReward(
        rawPayloadOrId: widget.bearingId,
        sourceModule: widget.sourceModule,
        supplierName: name,
        supplierContact: contact,
      );

      if (!mounted) return;

      if (result.rewardAwarded) {
        Navigator.pop(context, result);
      } else {
        setState(() => _isSubmitting = false);
        AppSnackBar.showError(
          context,
          result.message.isNotEmpty
              ? result.message
              : 'Unable to claim reward points for this bearing.',
        );
        if (result.alreadyClaimed || result.isUserBlocked) {
          Navigator.pop(context, result);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      AppSnackBar.showError(context, 'Claim failed: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.stars_rounded,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Claim Reward Points',
                  style: AppTypography.headlineSm.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  'Bearing Serial: ${widget.bearingId}',
                  style: AppTypography.caption.copyWith(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Where did you purchase this bearing from?',
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Supplier Name and Contact Number are mandatory fields to claim your Reward Points.',
                      style: AppTypography.caption.copyWith(
                        color: const Color(0xFF334155),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Supplier Name (Mandatory)
              Row(
                children: [
                  Text(
                    'Supplier Name',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Mandatory',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _supplierNameCtrl,
                enabled: !_isSubmitting,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Enter supplier / vendor name',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                  prefixIcon: const Icon(Icons.store_rounded, size: 20, color: AppColors.primary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Supplier name is mandatory. Please enter where you purchased the bearing from.';
                  }
                  if (val.trim().length < 2) {
                    return 'Supplier name must be at least 2 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Supplier Contact Number (Mandatory)
              Row(
                children: [
                  Text(
                    'Supplier Contact Number',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Mandatory',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _supplierContactCtrl,
                enabled: !_isSubmitting,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: 'Enter supplier 10-digit mobile number',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                  prefixIcon: const Icon(Icons.phone_outlined, size: 20, color: AppColors.primary),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Supplier contact number is mandatory.';
                  }
                  final clean = val.replaceAll(RegExp(r'[^0-9]'), '');
                  if (clean.length < 7) {
                    return 'Please enter a valid phone number (at least 7 to 10 digits).';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: Text(
            'Skip / Later',
            style: TextStyle(
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
          onPressed: _isSubmitting ? null : _submitClaim,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text(
                  'SUBMIT & CLAIM POINTS',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
        ),
      ],
    );
  }
}

