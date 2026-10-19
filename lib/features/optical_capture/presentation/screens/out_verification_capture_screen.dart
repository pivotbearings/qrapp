import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../../bearing_verification/data/repositories/bearing_repository.dart';
import '../../domain/services/image_compression_service.dart';

class OutVerificationCaptureScreen extends StatefulWidget {
  final String bearingId;

  const OutVerificationCaptureScreen({super.key, required this.bearingId});

  @override
  State<OutVerificationCaptureScreen> createState() =>
      _OutVerificationCaptureScreenState();
}

class _OutVerificationCaptureScreenState
    extends State<OutVerificationCaptureScreen> {
  final BearingRepository _repository = BearingRepositoryImpl();
  bool _isProcessing = false;
  String _computedHash = '[PENDING TRIGGER]';

  Future<void> _captureAndProcessProof() async {
    setState(() => _isProcessing = true);

    // Simulate raw optical capture buffer (100x100 dummy bitmap)
    final dummyBytes = Uint8List.fromList(List.generate(2048, (i) => (i * 17) % 255));
    final processed = await ImageCompressionService.processProofImage(dummyBytes);

    setState(() {
      _computedHash = processed.sha256Hash;
    });

    // Mark bearing OUT in repository with generated hash
    await _repository.markBearingOut(widget.bearingId, proofImageHash: processed.sha256Hash);

    if (!mounted) return;

    Navigator.pushReplacementNamed(
      context,
      AppRoutes.outResult,
      arguments: widget.bearingId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const IndustrialAppBar(title: 'Bearing Lifecycle'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.gutterMobile),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Removal Image Capture', style: AppTypography.headlineLgMobile),
              const SizedBox(height: AppDimensions.spaceMd),

              // Optical Reticle Viewfinder Container
              AspectRatio(
                aspectRatio: 4 / 5,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: AppDimensions.borderRadiusCard,
                    border: Border.all(color: AppColors.primary, width: 2.0),
                  ),
                  padding: const EdgeInsets.all(AppDimensions.spaceMd),
                  child: Stack(
                    children: [
                      // Telemetry metadata header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('CAM: OUT-OPTICAL-02', style: AppTypography.caption),
                              Text('EXP: 1/500s | F2.8', style: AppTypography.caption),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('UID: ${widget.bearingId}', style: AppTypography.caption),
                              const Text('[CALIBRATED]', style: AppTypography.caption),
                            ],
                          ),
                        ],
                      ),

                      // Reticle alignment center
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.primary, width: 1.5),
                              ),
                              child: Center(
                                child: Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.primary, width: 1.0),
                                  ),
                                  child: const Icon(Icons.center_focus_strong, size: 28, color: AppColors.primary),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.primary, width: 1.0),
                                borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                              ),
                              child: const Text(
                                '[AXIAL REMOVAL VECTOR: OK]',
                                style: AppTypography.caption,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Bottom encryption / status bar
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text('OPTICAL SHUTTER READY', style: AppTypography.caption),
                                  ],
                                ),
                                const Text('ISO 100', style: AppTypography.caption),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'TELEMETRY HASH: $_computedHash',
                              style: AppTypography.caption.copyWith(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppDimensions.spaceMd),

              // Verification Note Card
              IndustrialCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.verified_user, color: AppColors.primary, size: 20),
                    const SizedBox(width: AppDimensions.spaceSm),
                    const Expanded(
                      child: Text(
                        'Optical removal proof will be compressed, timestamped, cryptographically hashed with SHA-256, and permanently attached to the bearing audit trail. Once submitted, this bearing lifecycle ends permanently.',
                        style: AppTypography.bodyMd,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.spaceLg),

              IndustrialButton(
                label: 'Capture Optical Proof & Submit OUT',
                icon: Icons.camera_alt,
                isLoading: _isProcessing,
                onPressed: _captureAndProcessProof,
              ),

              const SizedBox(height: AppDimensions.spaceSm),

              IndustrialButton.secondary(
                label: 'Cancel',
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(height: AppDimensions.spaceXl),
            ],
          ),
        ),
      ),
    );
  }
}
