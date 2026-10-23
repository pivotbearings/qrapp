import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../data/services/bearing_authentication_service.dart';
import '../../domain/models/bearing_authentication_result.dart';
import '../../../rewards/domain/models/reward_models.dart';

enum AuthenticationViewStep {
  landing,
  scanner,
  verifying,
  result,
}

/// Pivot Bearings India - Bearing Authentication Page
///
/// Full-feature, authoritative authenticity verification for registered users:
/// - "Authenticate Your Bearing" CTA opening the mobile/web QR scanner
/// - First scan: Prominent green layout, “Authentic Pivot Bearing.” Confirms authentication.
/// - Second scan: Confirms authentic bearing, notes it has already been scanned once.
/// - Third+ scans: Displays total number of previous scans, confirms authentic bearing.
/// - Invalid scan: Clear red warning, “Invalid Bearing Code” / “Bearing Authenticity Could Not Be Verified.”
/// - 100% mobile responsive for compact Android screens with zero overlapping or clipped widgets.
class BearingAuthenticationScreen extends StatefulWidget {
  final String? initialPayload;

  const BearingAuthenticationScreen({
    super.key,
    this.initialPayload,
  });

  @override
  State<BearingAuthenticationScreen> createState() =>
      _BearingAuthenticationScreenState();
}

class _BearingAuthenticationScreenState
    extends State<BearingAuthenticationScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  AuthenticationViewStep _currentStep = AuthenticationViewStep.landing;
  BearingAuthenticationResult? _authResult;
  MobileScannerController? _scannerController;
  late AnimationController _laserAnimController;

  bool _isTorchOn = false;
  bool _isCameraFacingBack = true;
  bool _cameraPermissionDenied = false;
  String? _lastScannedCode;
  final TextEditingController _manualInputController = TextEditingController();

  // Curated High-Contrast Colors for Industrial Validation
  static const Color _greenPrimary = Color(0xFF0D8A4E);
  static const Color _greenBackground = Color(0xFFE8F5E9);
  static const Color _greenBorder = Color(0xFF2E7D32);
  static const Color _greenTextDark = Color(0xFF1B5E20);

  static const Color _redPrimary = Color(0xFFD32F2F);
  static const Color _redBackground = Color(0xFFFFEBEE);
  static const Color _redBorder = Color(0xFFC62828);
  static const Color _redTextDark = Color(0xFFB71C1C);

  // Slight Yellow theme for all repeat/subsequent scans (2nd, 3rd, 4th, etc.)
  static const Color _yellowPrimary = Color(0xFFCA8A04);
  static const Color _yellowBackground = Color(0xFFFEF9C3); // Clear slight yellow (Tailwind Yellow-100)
  static const Color _yellowBackgroundSubtle = Color(0xFFFEFCE8); // Very soft pastel yellow-50
  static const Color _yellowBorder = Color(0xFFEAB308); // Vibrant yellow border
  static const Color _yellowTextDark = Color(0xFF713F12); // High-contrast warm dark yellow text
  static const Color _yellowSubhead = Color(0xFF854D0E);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _laserAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);

    if (widget.initialPayload != null && widget.initialPayload!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _executeAuthentication(widget.initialPayload!);
      });
    }
  }

  void _initScanner() {
    _scannerController?.dispose();
    _scannerController = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: _isCameraFacingBack ? CameraFacing.back : CameraFacing.front,
      torchEnabled: _isTorchOn,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_scannerController == null || !_scannerController!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _scannerController?.stop();
    } else if (state == AppLifecycleState.resumed && _currentStep == AuthenticationViewStep.scanner) {
      _scannerController?.start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _laserAnimController.dispose();
    _scannerController?.dispose();
    _manualInputController.dispose();
    super.dispose();
  }

  void _openScanner() {
    _initScanner();
    setState(() {
      _currentStep = AuthenticationViewStep.scanner;
      _cameraPermissionDenied = false;
      _lastScannedCode = null;
    });
  }

  void _closeScanner() {
    _scannerController?.stop();
    setState(() {
      _currentStep = AuthenticationViewStep.landing;
    });
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_currentStep != AuthenticationViewStep.scanner) return;

    for (final barcode in capture.barcodes) {
      if (barcode.format != BarcodeFormat.qrCode) continue;
      final rawValue = barcode.rawValue?.trim();
      if (rawValue == null || rawValue.isEmpty) continue;
      if (rawValue == _lastScannedCode) continue;

      _lastScannedCode = rawValue;
      await _executeAuthentication(rawValue);
      break;
    }
  }

  Future<void> _executeAuthentication(String payload) async {
    setState(() {
      _currentStep = AuthenticationViewStep.verifying;
    });
    await _scannerController?.stop();

    try {
      final result = await BearingAuthenticationService.authenticateBearing(payload);
      if (mounted) {
        setState(() {
          _authResult = result;
          _currentStep = AuthenticationViewStep.result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _authResult = BearingAuthenticationResult.invalid(
            rawPayload: payload,
            message: 'Authentication check failed: ${e.toString()}',
          );
          _currentStep = AuthenticationViewStep.result;
        });
      }
    }
  }

  void _toggleTorch() {
    if (_scannerController == null) return;
    setState(() => _isTorchOn = !_isTorchOn);
    _scannerController?.toggleTorch();
  }

  void _switchCamera() {
    if (_scannerController == null) return;
    setState(() => _isCameraFacingBack = !_isCameraFacingBack);
    _scannerController?.switchCamera();
  }

  void _showManualEntryDialog() {
    _manualInputController.clear();
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
            side: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.qr_code_2_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Enter Bearing Code',
                  style: AppTypography.headlineSm.copyWith(color: AppColors.primary),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Type the bearing serial number or paste the QR payload printed on the box.',
                  style: AppTypography.caption.copyWith(color: Colors.black87),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _manualInputController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'e.g. PB-9402-XJ',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                      borderSide: const BorderSide(color: AppColors.primary, width: 2.0),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Quick Test Samples:',
                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildTestChip('PB-9402-XJ', 'PB-9402-XJ (Seed Valid)'),
                    _buildTestChip('PB-8812-KR', 'PB-8812-KR (Valid)'),
                    _buildTestChip('INVALID-CODE-999', 'Fake Code (Invalid)'),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: AppTypography.labelMd.copyWith(color: AppColors.primary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                ),
              ),
              onPressed: () {
                final code = _manualInputController.text.trim();
                if (code.isNotEmpty) {
                  Navigator.pop(ctx);
                  _executeAuthentication(code);
                }
              },
              child: const Text('Verify'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTestChip(String value, String label) {
    return InkWell(
      onTap: () {
        _manualInputController.text = value;
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.primary, width: 1.0),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: IndustrialAppBar(
        title: 'Bearing Authentication',
        onBack: () {
          if (_currentStep == AuthenticationViewStep.scanner) {
            _closeScanner();
          } else if (_currentStep == AuthenticationViewStep.result) {
            setState(() => _currentStep = AuthenticationViewStep.landing);
          } else {
            Navigator.maybePop(context);
          }
        },
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: _buildCurrentView(constraints),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCurrentView(BoxConstraints constraints) {
    switch (_currentStep) {
      case AuthenticationViewStep.landing:
        return _buildLandingView(constraints);
      case AuthenticationViewStep.scanner:
        return _buildScannerView(constraints);
      case AuthenticationViewStep.verifying:
        return _buildVerifyingView();
      case AuthenticationViewStep.result:
        return _buildResultView(constraints);
    }
  }

  // ===========================================================================
  // 1. LANDING VIEW: Intro & "Authenticate Your Bearing" CTA
  // ===========================================================================
  Widget _buildLandingView(BoxConstraints constraints) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.gutterMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero Official Authenticity Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              border: Border.all(color: AppColors.primary, width: 1.5),
            ),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 2.0),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.verified_user_rounded,
                      size: 36,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'PIVOT BEARINGS INDIA',
                  style: AppTypography.labelMd.copyWith(
                    letterSpacing: 1.2,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Bearing Authentication Portal',
                  style: AppTypography.headlineSm.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),

          // Primary CTA Button: Authenticate Your Bearing
          Material(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(50),
            elevation: 2,
            child: InkWell(
              onTap: _openScanner,
              borderRadius: BorderRadius.circular(50),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: AppColors.background,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Text(
                        'Authenticate Your Bearing',
                        style: AppTypography.labelLg.copyWith(
                          color: AppColors.background,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.background,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: AppDimensions.spaceSm),

          // Secondary CTA: Enter Serial Manually
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _showManualEntryDialog,
            icon: const Icon(Icons.keyboard_alt_outlined, size: 20),
            label: Text(
              'Enter Bearing Serial Manually',
              style: AppTypography.labelMd.copyWith(fontWeight: FontWeight.bold),
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. SCANNER VIEW: Full-screen Camera Viewport with Reticle & Controls
  // ===========================================================================
  Widget _buildScannerView(BoxConstraints constraints) {
    final scanBoxSize = (constraints.maxWidth * 0.72).clamp(200.0, 280.0);

    return Column(
      children: [
        // Top Scanner Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.primary,
          child: Row(
            children: [
              const Icon(Icons.qr_code_scanner, color: AppColors.background, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Scan QR Code on Bearing Box',
                  style: AppTypography.labelMd.copyWith(
                    color: AppColors.background,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.background),
                tooltip: 'Close Scanner',
                onPressed: _closeScanner,
              ),
            ],
          ),
        ),

        // Camera Feed / Reticle Area
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

              // Semi-transparent overlay mask with cutout
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (ctx, box) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Viewfinder Box
                        Container(
                          width: scanBoxSize,
                          height: scanBoxSize,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2.0),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(80),
                                spreadRadius: 1000,
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              // 4 Corner Brackets
                              ..._buildCornerBrackets(),

                              // Animated Scanning Laser Bar
                              AnimatedBuilder(
                                animation: _laserAnimController,
                                builder: (context, child) {
                                  return Positioned(
                                    top: _laserAnimController.value * (scanBoxSize - 20) + 10,
                                    left: 12,
                                    right: 12,
                                    child: Container(
                                      height: 2.5,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00FF66),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF00FF66).withAlpha(180),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        // Alignment Instruction Pill
                        Positioned(
                          top: (box.maxHeight / 2) - (scanBoxSize / 2) - 48,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(180),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white70, width: 1.0),
                            ),
                            child: const Text(
                              'ALIGN BEARING QR CODE WITHIN FRAME',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Bottom Controls Bar (Flash, Camera Switch, Manual Entry)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: _toggleTorch,
                icon: Icon(
                  _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: AppColors.primary,
                ),
                tooltip: 'Toggle Flash',
              ),
              if (!kIsWeb)
                IconButton(
                  onPressed: _switchCamera,
                  icon: const Icon(Icons.flip_camera_ios_rounded, color: AppColors.primary),
                  tooltip: 'Switch Camera',
                ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _showManualEntryDialog,
                  icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
                  label: const Text(
                    'Manual Entry',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCornerBrackets() {
    const double length = 22.0;
    const double thickness = 3.5;
    const Color cornerColor = Color(0xFF00FF66);

    return [
      // Top-Left
      Positioned(top: 0, left: 0, child: Container(width: length, height: thickness, color: cornerColor)),
      Positioned(top: 0, left: 0, child: Container(width: thickness, height: length, color: cornerColor)),
      // Top-Right
      Positioned(top: 0, right: 0, child: Container(width: length, height: thickness, color: cornerColor)),
      Positioned(top: 0, right: 0, child: Container(width: thickness, height: length, color: cornerColor)),
      // Bottom-Left
      Positioned(bottom: 0, left: 0, child: Container(width: length, height: thickness, color: cornerColor)),
      Positioned(bottom: 0, left: 0, child: Container(width: thickness, height: length, color: cornerColor)),
      // Bottom-Right
      Positioned(bottom: 0, right: 0, child: Container(width: length, height: thickness, color: cornerColor)),
      Positioned(bottom: 0, right: 0, child: Container(width: thickness, height: length, color: cornerColor)),
    ];
  }

  Widget _buildNativeCameraViewport() {
    if (_scannerController == null) return const SizedBox.shrink();
    return MobileScanner(
      controller: _scannerController!,
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
                onPressed: () => _scannerController?.start(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWebCameraViewport() {
    if (_scannerController == null) return const SizedBox.shrink();
    return MobileScanner(
      controller: _scannerController!,
      onDetect: _onBarcodeDetected,
    );
  }

  Widget _buildPermissionDeniedView() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(AppDimensions.gutterDesktop),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, size: 54, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              'Camera Access Required',
              style: AppTypography.headlineSm.copyWith(color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please allow camera permission to scan bearing QR codes, or verify by typing the serial number manually.',
              style: AppTypography.bodySm,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            IndustrialButton(
              label: 'ENTER SERIAL MANUALLY',
              onPressed: _showManualEntryDialog,
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 3. VERIFYING VIEW: Industrial Loading Indicator
  // ===========================================================================
  Widget _buildVerifyingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.gutterMobile),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 52,
              height: 52,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 3.5,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Authenticating Bearing...',
              style: AppTypography.headlineSm.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cross-referencing cryptographic records in Pivot Bearings India registry...',
              style: AppTypography.caption.copyWith(color: Colors.black87),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 4. RESULT VIEW: Strictly handles 1st, 2nd, 3rd+, and Invalid scan states
  // ===========================================================================
  Widget _buildResultView(BoxConstraints constraints) {
    final result = _authResult ?? BearingAuthenticationResult.invalid();

    if (result.isAlreadyOut) {
      return _buildAlreadyOutResultView(result);
    } else if (result.isAuthentic) {
      return _buildAuthenticResultView(result);
    } else {
      return _buildInvalidResultView(result);
    }
  }

  /// Minimalist decommissioned screen: "bearing marked as out, cant scan again."
  Widget _buildAlreadyOutResultView(BearingAuthenticationResult result) {
    final bearingIdStr = result.bearingId ?? result.rawPayload ?? 'N/A';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.gutterMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              border: Border.all(color: Colors.black12, width: 1.2),
            ),
            child: Column(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey[300]!, width: 1.5),
                  ),
                  child: Icon(
                    Icons.do_not_disturb_alt_rounded,
                    size: 32,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'bearing marked as out, cant scan again.',
                  style: AppTypography.headlineSm.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Bearing ID: $bearingIdStr',
                  style: AppTypography.bodySm.copyWith(
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spaceMd),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () {
              Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.customerHome,
                (route) => false,
              );
            },
            child: Text(
              'Back to Dashboard',
              style: AppTypography.labelMd.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Authentic Bearing Layout (Green Theme with 1st, 2nd, 3rd+ scan messaging)
  Widget _buildAuthenticResultView(BearingAuthenticationResult result) {
    final isFirst = result.isFirstScan;
    final isSecond = result.isSecondScan;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.gutterMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dynamic Success/Alert Card (Green for 1st scan, Slight Yellow for repeat scans)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isFirst ? _greenBackground : _yellowBackground,
              borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              border: Border.all(
                color: isFirst ? _greenBorder : _yellowBorder,
                width: 2.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isFirst ? _greenPrimary : _yellowBorder).withAlpha(40),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Verified or Warning Icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: isFirst ? _greenPrimary : _yellowPrimary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3.0),
                  ),
                  child: Center(
                    child: Icon(
                      isFirst ? Icons.check_circle_rounded : Icons.history_toggle_off_rounded,
                      size: 44,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Success or Previously Scanned Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: isFirst ? _greenPrimary : _yellowPrimary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isFirst ? 'OFFICIALLY REGISTERED BEARING • 1ST SCAN' : 'PREVIOUSLY SCANNED BEARING (${result.totalScanCount} SCANS)',
                    style: AppTypography.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Headline
                Text(
                  isFirst ? 'Authentic Pivot Bearing' : 'Previously Scanned Bearing',
                  style: AppTypography.headlineSm.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    color: isFirst ? _greenTextDark : _yellowTextDark,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),

                // Subhead
                Text(
                  isFirst
                      ? 'First Recorded Scan · Bearing Successfully Authenticated'
                      : 'This QR code has been scanned ${result.totalScanCount} times before',
                  style: AppTypography.labelMd.copyWith(
                    color: isFirst ? _greenPrimary : _yellowSubhead,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),

          // Condition-Specific Scan Message Banner
          if (isFirst)
            _buildFirstScanBanner(result)
          else if (isSecond)
            _buildSecondScanBanner(result)
          else
            _buildThirdPlusScanBanner(result),

          if (result.rewardClaim?.rewardAwarded == true) ...[
            const SizedBox(height: AppDimensions.spaceSm),
            _buildRewardClaimCelebrationBanner(result.rewardClaim!),
          ] else if (result.rewardClaim?.isUserBlocked == true) ...[
            const SizedBox(height: AppDimensions.spaceSm),
            _buildRewardBlockedAccountNotice(result.rewardClaim!),
          ] else if (result.rewardClaim?.alreadyClaimed == true) ...[
            const SizedBox(height: AppDimensions.spaceSm),
            _buildRewardAlreadyClaimedNotice(),
          ],

          const SizedBox(height: AppDimensions.spaceMd),

          // Bearing Authentication Scan Record
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isFirst ? Colors.white : _yellowBackgroundSubtle,
              borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              border: Border.all(
                color: isFirst ? AppColors.primary : _yellowBorder,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'BEARING SPECIFICATIONS',
                  style: AppTypography.labelMd.copyWith(
                    fontWeight: FontWeight.w900,
                    color: isFirst ? AppColors.primary : _yellowTextDark,
                    letterSpacing: 0.5,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: isFirst ? const Color(0xFFDCFCE7) : _yellowBackground,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isFirst ? const Color(0xFF16A34A) : _yellowBorder,
                      width: 1.2,
                    ),
                  ),
                  child: Text(
                    'Total Scans: ${result.totalScanCount}',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w900,
                      color: isFirst ? const Color(0xFF15803D) : _yellowTextDark,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),

          // Primary CTA: Back to Dashboard
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () {
              Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.customerHome,
                (route) => false,
              );
            },
            child: Text(
              'Back to Dashboard',
              style: AppTypography.labelMd.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.spaceMd),
        ],
      ),
    );
  }

  // --- 1st Scan Banner (Prominent Green Confirmation) ---
  Widget _buildFirstScanBanner(BearingAuthenticationResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        border: Border.all(color: _greenBorder, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified, color: _greenPrimary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'First Scan Verified',
                  style: AppTypography.labelMd.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _greenTextDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Clearly confirmed that this bearing has been successfully authenticated. This is the first recorded scan for this official QR code.',
                  style: AppTypography.bodySm.copyWith(
                    color: Colors.black87,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 2nd Scan Banner (Already Scanned Once Notice) ---
  Widget _buildSecondScanBanner(BearingAuthenticationResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _yellowBackground,
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        border: Border.all(color: _yellowBorder, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.history_toggle_off_rounded, color: _yellowPrimary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Already Scanned Once',
                  style: AppTypography.labelMd.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _yellowTextDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This QR code has already been scanned once and belongs to an authentic bearing.',
                  style: AppTypography.bodySm.copyWith(
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total Previous Scans: 1 | Current Scan: #2',
                  style: AppTypography.caption.copyWith(color: _yellowSubhead, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 3rd+ Scan Banner (Total Previous Scans Counter) ---
  Widget _buildThirdPlusScanBanner(BearingAuthenticationResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _yellowBackground,
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        border: Border.all(color: _yellowBorder, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.pin_outlined, color: _yellowPrimary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Multiple Previous Scans Detected (${result.totalScanCount} Total)',
                  style: AppTypography.labelMd.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _yellowTextDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This QR code has already been scanned ${result.previousScanCount} times. Authentic Pivot Bearing.',
                  style: AppTypography.bodySm.copyWith(
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total Scans: ${result.totalScanCount} | Previous Scans: ${result.previousScanCount}',
                  style: AppTypography.caption.copyWith(color: _yellowSubhead, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardClaimCelebrationBanner(RewardClaimResult claim) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        border: Border.all(color: AppColors.primary, width: 1.8),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.stars, color: Colors.white, size: 26),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '1ST SCAN REWARD CLAIMED!',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '+${claim.pointsEarned} Points Credited!',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
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

  Widget _buildRewardAlreadyClaimedNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        border: Border.all(color: AppColors.primary, width: 1.2),
      ),
      child: const Row(
        children: [
          Icon(Icons.stars, color: AppColors.primary, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Reward points for this bearing have already been claimed on first registration.',
              style: TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardBlockedAccountNotice(RewardClaimResult claim) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        border: Border.all(color: AppColors.primary.withAlpha(60), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AUTHENTIC BEARING • STANDARD ACCOUNT',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  claim.message.isNotEmpty
                      ? claim.message
                      : 'Bearing verified authentic! Reward points are currently inactive for this account profile. For program details, please contact Pivot Bearings support.',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Invalid Bearing Layout (Red Theme Warning)
  Widget _buildInvalidResultView(BearingAuthenticationResult result) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.gutterMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Red Danger Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _redBackground,
              borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              border: Border.all(color: _redBorder, width: 2.0),
              boxShadow: [
                BoxShadow(
                  color: _redPrimary.withAlpha(25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Red Warning Hexagon Icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _redPrimary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3.0),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.gpp_bad_rounded,
                      size: 44,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Critical Danger Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _redPrimary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'UNREGISTERED IDENTIFIER',
                    style: AppTypography.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Headline: "Invalid Bearing Code"
                Text(
                  'Invalid Bearing Code',
                  style: AppTypography.headlineSm.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    color: _redTextDark,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),

                // Subhead: "Bearing Authenticity Could Not Be Verified"
                Text(
                  'Bearing Authenticity Could Not Be Verified',
                  style: AppTypography.labelMd.copyWith(
                    color: _redPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),

          // Prominent Warning Box: Never identify an unregistered code as genuine
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              border: Border.all(color: _redBorder, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: _redPrimary, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'CRITICAL AUTHENTICITY ALERT',
                      style: AppTypography.labelMd.copyWith(
                        fontWeight: FontWeight.w900,
                        color: _redTextDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Never identify an unregistered code as genuine.',
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _redTextDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'The scanned QR code does not match any registered bearing record in the database of Pivot Bearings India. It may be counterfeit, altered, or damaged. Do not install this bearing into machinery.',
                  style: AppTypography.bodySm.copyWith(
                    color: Colors.black87,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),

          // Scanned Identifier Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              border: Border.all(color: Colors.black12, width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SCANNED DATA',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  result.bearingId ?? result.rawPayload ?? 'Unknown Payload',
                  style: AppTypography.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    color: _redTextDark,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Verification Status: UNREGISTERED / NOT FOUND',
                  style: AppTypography.caption.copyWith(
                    color: _redPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),

          // Quality Helpline & Official Verification Support Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              border: Border.all(color: AppColors.primary, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.support_agent_rounded, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Report Counterfeits or Inquire',
                      style: AppTypography.labelMd.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Contact the Pivot Bearings India Quality Assurance Directorate:\n'
                  '• Helpline: +91 98988 57198\n'
                  '• Email: pivotbearings@gmail.com\n'
                  '• Portal: https://www.pivotbearingsindia.com/',
                  style: AppTypography.bodySm.copyWith(
                    color: Colors.black87,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),

          // Action: Back to Dashboard
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () {
              Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.customerHome,
                (route) => false,
              );
            },
            child: Text(
              'Back to Dashboard',
              style: AppTypography.labelMd.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.spaceMd),
        ],
      ),
    );
  }
}
