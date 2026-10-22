import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../../../core/widgets/industrial_status_badge.dart';
import '../../../../core/widgets/industrial_text_field.dart';
import '../../../bearing_verification/data/repositories/bearing_repository.dart';
import '../../../bearing_verification/domain/models/qr_verification_result.dart';
import '../../../../core/widgets/app_snack_bar.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late MobileScannerController _scannerController;
  late AnimationController _laserAnimController;

  final BearingRepository _bearingRepository = BearingRepositoryImpl();

  bool _isTorchOn = false;
  bool _isProcessing = false;
  bool _cameraPermissionDenied = false;
  String? _lastScannedPayload;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _scannerController = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    _laserAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_scannerController.value.isInitialized) return;

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _scannerController.stop();
    } else if (state == AppLifecycleState.resumed) {
      if (!_isProcessing) {
        _scannerController.start();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _laserAnimController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  /// Handles incoming barcode detections
  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_isProcessing) return;

    for (final barcode in capture.barcodes) {
      if (barcode.format != BarcodeFormat.qrCode) continue;
      final rawValue = barcode.rawValue?.trim();
      if (rawValue == null || rawValue.isEmpty) continue;
      if (rawValue == _lastScannedPayload && _isProcessing) continue;

      _lastScannedPayload = rawValue;
      await _processScannedPayload(rawValue);
      break;
    }
  }

  /// Main scan processing pipeline
  Future<void> _processScannedPayload(String payload) async {
    setState(() => _isProcessing = true);
    await _scannerController.stop();

    try {
      final result = await _bearingRepository.verifyScannedPayload(payload);
      if (!mounted) return;

      if (result.rewardClaim?.rewardAwarded == true) {
        AppSnackBar.showSuccess(
          context,
          '🎉 1st Scan Reward: +${result.rewardClaim!.pointsEarned} Points (≈ ₹${result.rewardClaim!.amountInr.toStringAsFixed(2)}) Credited!',
        );
      } else if (result.rewardClaim?.isUserBlocked == true) {
        AppSnackBar.showInfo(
          context,
          'Bearing verified authentic. Account is in standard mode without promotional reward points.',
        );
      }

      final isDecommissioned = result.status == QrVerificationStatus.decommissionedOut ||
          result.currentLifecycleState == 'CURRENTLY_OUT' ||
          result.currentLifecycleState == 'FINAL_OUT' ||
          result.currentLifecycleState == 'DECOMMISSIONED';

      // --- ROUTE TO STEP-BY-STEP FLOW ON VALID SCAN ---
      if (result.canMarkIn && !isDecommissioned) {
        // Guide user through clean 3-step Mark IN process
        Navigator.pushNamed(
          context,
          AppRoutes.inConfirmation,
          arguments: result.bearingId,
        ).then((_) => _resumeScanning());
        return;
      } else if (result.canMarkOut && !isDecommissioned) {
        // Guide user through Mark OUT removal confirmation
        Navigator.pushNamed(
          context,
          AppRoutes.outConfirmation,
          arguments: result.bearingId,
        ).then((_) => _resumeScanning());
        return;
      }

      // For non-actionable states (invalid, blocked, decommissioned), show info modal
      _showVerificationModal(result);
    } catch (e) {
      if (mounted) {
        _showVerificationModal(
          QrVerificationResult.invalid(
            message: 'Verification error: ${e.toString()}',
          ),
        );
      }
    }
  }

  void _resumeScanning() {
    if (mounted) {
      setState(() {
        _isProcessing = false;
        _lastScannedPayload = null;
      });
      _scannerController.start();
    }
  }

  void _toggleTorch() {
    _scannerController.toggleTorch();
    setState(() => _isTorchOn = !_isTorchOn);
  }

  void _showManualEntryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
          side: const BorderSide(color: AppColors.primary, width: 2.0),
        ),
        title: const Text('Enter Bearing Serial', style: AppTypography.headlineSm),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the bearing serial number manually if the QR is physically damaged.',
              style: AppTypography.bodySm,
            ),
            const SizedBox(height: AppDimensions.spaceSm),
            IndustrialTextField(
              controller: controller,
              label: 'Bearing Serial / QR ID',
              hintText: 'e.g. PB-1001-AA',
              uppercase: true,
            ),
          ],
        ),
        actions: [
          IndustrialButton.secondary(
            label: 'Cancel',
            onPressed: () => Navigator.pop(ctx),
            height: 40,
            width: 100,
          ),
          const SizedBox(width: 8),
          IndustrialButton(
            label: 'Verify',
            onPressed: () {
              final id = controller.text.trim().toUpperCase();
              Navigator.pop(ctx);
              if (id.isNotEmpty) _processScannedPayload(id);
            },
            height: 40,
            width: 110,
          ),
        ],
      ),
    );
  }

  /// Shows a status modal for non-actionable (error/info) scan results
  void _showVerificationModal(QrVerificationResult result) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusMedium)),
        side: BorderSide(color: AppColors.primary, width: 2.0),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(AppDimensions.gutterDesktop),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(result.displayTitle, style: AppTypography.labelMd),
                    IndustrialStatusBadge(
                      statusText: _getStatusBadgeText(result.status),
                      isDanger: result.status == QrVerificationStatus.qrUnknownOrInvalid ||
                                result.status == QrVerificationStatus.qrBlocked ||
                                result.isExpired,
                      isSuccess: result.status == QrVerificationStatus.validNotActivated ||
                                 result.status == QrVerificationStatus.validWarrantyActive,
                    ),
                  ],
                ),
                const SizedBox(height: AppDimensions.spaceMd),

                // Case: UNKNOWN or INVALID (Rendered in prominent RED)
                if (result.status == QrVerificationStatus.qrUnknownOrInvalid)
                  _buildInfoCard(
                    title: 'INVALID QR CODE - NOT AUTHENTIC',
                    description: result.errorMessage ??
                        'This QR code is not recognized in the Pivot Bearings registry. Component authenticity cannot be verified. Do not install.',
                    icon: Icons.gpp_bad_rounded,
                    isDanger: true,
                  )

                // Case: BLOCKED
                else if (result.status == QrVerificationStatus.qrBlocked)
                  _buildInfoCard(
                    title: 'BEARING BLOCKED',
                    description: 'Reason: ${result.flagReason ?? "Flagged for inspection."}\nInstallation and removal are prohibited.',
                    icon: Icons.block,
                    isDanger: true,
                  )

                // Case: DECOMMISSIONED (lifecycle ended)
                else if (result.status == QrVerificationStatus.decommissionedOut ||
                    result.currentLifecycleState == 'CURRENTLY_OUT' ||
                    result.currentLifecycleState == 'FINAL_OUT' ||
                    result.currentLifecycleState == 'DECOMMISSIONED')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildInfoCard(
                        title: 'BEARING MARKED AS OUT',
                        description: 'This bearing has been permanently decommissioned and cannot be scanned for Bearing In or Authentication.',
                        icon: Icons.do_not_disturb_on_rounded,
                        isDanger: true,
                      ),
                      const SizedBox(height: AppDimensions.spaceSm),
                      IndustrialCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(result.bearingId ?? 'N/A', style: AppTypography.headlineSm),
                                Text(result.modelNumber ?? '', style: AppTypography.caption),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text('STATUS: DECOMMISSIONED', style: AppTypography.caption),
                          ],
                        ),
                      ),
                    ],
                  )

                // Case: NETWORK
                else if (result.status == QrVerificationStatus.networkUnavailable)
                  _buildInfoCard(
                    title: 'NO NETWORK CONNECTION',
                    description: 'Cannot connect to registry. Verification requires internet access.',
                    icon: Icons.wifi_off_outlined,
                  )

                // Case: WARRANTY INFO (already activated)
                else
                  IndustrialCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(result.bearingId ?? 'PB-UNKNOWN', style: AppTypography.headlineSm),
                            Text(result.modelNumber ?? '', style: AppTypography.caption),
                          ],
                        ),
                        const SizedBox(height: AppDimensions.spaceSm),
                        Text('PLAN: ${result.warrantyPlanTitle ?? "${result.warrantyDurationMonths ?? 6} Months"}', style: AppTypography.bodySm),
                        if (result.firstInTimestamp != null)
                          Text('ACTIVATED: ${result.firstInTimestamp!.toLocal().toString().split('.')[0]}', style: AppTypography.caption),
                        if (result.warrantyExpiryTimestamp != null)
                          Text(
                            'EXPIRES: ${result.warrantyExpiryTimestamp!.toLocal().toString().split('.')[0]} ${result.isExpired ? "[EXPIRED]" : "[ACTIVE]"}',
                            style: AppTypography.caption.copyWith(
                              fontWeight: FontWeight.bold,
                              color: result.isExpired ? const Color(0xFFDC2626) : AppColors.primary,
                            ),
                          )
                        else
                          const Text('WARRANTY: NOT YET ACTIVATED', style: AppTypography.caption),
                      ],
                    ),
                  ),

                const SizedBox(height: AppDimensions.spaceLg),

                // Mark IN / Mark OUT action buttons when applicable
                if (result.canMarkIn) ...[
                  IndustrialButton.success(
                    label: 'MARK BEARING IN & SUBMIT',
                    icon: Icons.login,
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.pushNamed(
                        context,
                        AppRoutes.inConfirmation,
                        arguments: result.bearingId,
                      ).then((_) => _resumeScanning());
                    },
                  ),
                  const SizedBox(height: AppDimensions.spaceSm),
                ] else if (result.canMarkOut) ...[
                  IndustrialButton.danger(
                    label: 'MARK BEARING OUT & SUBMIT',
                    icon: Icons.logout,
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.pushNamed(
                        context,
                        AppRoutes.outConfirmation,
                        arguments: result.bearingId,
                      ).then((_) => _resumeScanning());
                    },
                  ),
                  const SizedBox(height: AppDimensions.spaceSm),
                ],

                // Action: SCAN AGAIN
                SizedBox(
                  width: double.infinity,
                  child: IndustrialButton.secondary(
                    label: 'SCAN AGAIN',
                    onPressed: () {
                      Navigator.pop(ctx);
                      _resumeScanning();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String description,
    required IconData icon,
    bool isDanger = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.spaceSm),
      decoration: BoxDecoration(
        color: isDanger ? const Color(0xFFFEF2F2) : AppColors.background,
        border: Border.all(
          color: isDanger ? const Color(0xFFDC2626) : AppColors.primary,
          width: 2.0,
        ),
        borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: isDanger ? const Color(0xFFDC2626) : AppColors.primary, size: 22),
              const SizedBox(width: AppDimensions.spaceSm),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.labelMd.copyWith(
                    color: isDanger ? const Color(0xFFDC2626) : AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spaceSm),
          Text(
            description,
            style: AppTypography.bodySm.copyWith(
              color: isDanger ? const Color(0xFF991B1B) : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusBadgeText(QrVerificationStatus status) {
    switch (status) {
      case QrVerificationStatus.validNotActivated:
        return 'VERIFIED';
      case QrVerificationStatus.validWarrantyActive:
        return 'WARRANTY ACTIVE';
      case QrVerificationStatus.warrantyExpired:
        return 'WARRANTY EXPIRED';
      case QrVerificationStatus.decommissionedOut:
        return 'DECOMMISSIONED';
      case QrVerificationStatus.qrBlocked:
        return 'BLOCKED';
      case QrVerificationStatus.qrUnknownOrInvalid:
        return 'INVALID QR';
      case QrVerificationStatus.networkUnavailable:
        return 'OFFLINE';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const IndustrialAppBar(title: 'Warranty — Mark Bearing IN / OUT'),
      body: SafeArea(
        child: Column(
          children: [
            // Instruction Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: AppColors.background,
              child: const Text(
                'Scan bearing QR code to mark IN (upload installation proof & activate warranty) or mark OUT.',
                style: AppTypography.caption,
                textAlign: TextAlign.center,
              ),
            ),

            // Camera Viewport
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_cameraPermissionDenied)
                    _buildPermissionDeniedView()
                  else if (kIsWeb)
                    _buildWebCameraViewport()
                  else
                    _buildNativeCameraViewport(),

                  _buildIndustrialReticle(),

                  // Status chip
                  Positioned(
                    top: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        border: Border.all(color: AppColors.primary, width: 1.5),
                        borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                      ),
                      child: Text(
                        _isProcessing
                            ? 'VERIFYING QR — CAMERA WILL OPEN...'
                            : 'AIM AT BEARING QR CODE',
                        style: AppTypography.caption,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Controls
            Container(
              padding: const EdgeInsets.all(AppDimensions.gutterDesktop),
              decoration: const BoxDecoration(
                color: AppColors.background,
                border: Border(top: BorderSide(color: AppColors.primary, width: 2.0)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _toggleTorch,
                    icon: Icon(
                      _isTorchOn ? Icons.flash_on : Icons.flash_off,
                      color: AppColors.primary,
                    ),
                    tooltip: 'Toggle Torch',
                  ),
                  const SizedBox(width: AppDimensions.spaceSm),
                  Expanded(
                    child: IndustrialButton.secondary(
                      label: 'ENTER SERIAL MANUALLY',
                      icon: Icons.keyboard_alt_outlined,
                      onPressed: _showManualEntryDialog,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNativeCameraViewport() {
    return MobileScanner(
      controller: _scannerController,
      onDetect: _onBarcodeDetected,
      errorBuilder: (context, error) {
        if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _cameraPermissionDenied = true);
          });
        }
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, size: 48, color: AppColors.primary),
              const SizedBox(height: 8),
              Text('Camera Error: ${error.errorCode.name}', style: AppTypography.bodySm),
              const SizedBox(height: 12),
              IndustrialButton.secondary(
                label: 'Retry',
                width: 120,
                onPressed: () => _scannerController.start(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWebCameraViewport() {
    return MobileScanner(
      controller: _scannerController,
      onDetect: _onBarcodeDetected,
    );
  }

  Widget _buildPermissionDeniedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 56, color: AppColors.primary),
            const SizedBox(height: AppDimensions.spaceMd),
            const Text('Camera Permission Required', style: AppTypography.headlineSm),
            const SizedBox(height: AppDimensions.spaceSm),
            const Text(
              'Please enable camera access in your device settings to scan QR codes.',
              style: AppTypography.bodySm,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDimensions.spaceLg),
            IndustrialButton(
              label: 'REQUEST PERMISSION',
              width: 240,
              onPressed: () {
                setState(() => _cameraPermissionDenied = false);
                _scannerController.start();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndustrialReticle() {
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        children: [
          Positioned(top: 0, left: 0, child: _corner(top: true, left: true)),
          Positioned(top: 0, right: 0, child: _corner(top: true, left: false)),
          Positioned(bottom: 0, left: 0, child: _corner(top: false, left: true)),
          Positioned(bottom: 0, right: 0, child: _corner(top: false, left: false)),
          AnimatedBuilder(
            animation: _laserAnimController,
            builder: (context, child) {
              return Positioned(
                top: _laserAnimController.value * 230,
                left: 10,
                right: 10,
                child: Container(height: 2.0, color: AppColors.primary),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _corner({required bool top, required bool left}) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        border: Border(
          top: top ? const BorderSide(color: AppColors.primary, width: 3.0) : BorderSide.none,
          bottom: !top ? const BorderSide(color: AppColors.primary, width: 3.0) : BorderSide.none,
          left: left ? const BorderSide(color: AppColors.primary, width: 3.0) : BorderSide.none,
          right: !left ? const BorderSide(color: AppColors.primary, width: 3.0) : BorderSide.none,
        ),
      ),
    );
  }
}
