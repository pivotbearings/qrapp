import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/whatsapp_icon.dart';
import '../../data/services/bearing_track_service.dart';
import '../../domain/models/bearing_track_result.dart';

enum TrackViewStep {
  landing,
  scanner,
  processing,
  result,
}

/// Pivot Bearings India - Track Your Bearing Page
///
/// Streamlined QR-Only Bearing IN and Bearing OUT Lifecycle Tracker:
/// - 100% QR-only workflow: NO photographs or image evidence required
/// - First scan (Bearing In): Green status/badge, confirms usage tracking started
/// - Second scan (Bearing Out): Red status/badge, calculates exact usage duration ("You used this bearing for X days")
/// - Repeated usage: Allows starting new Bearing In cycles while preserving historical completed records
/// - Fully mobile responsive for compact and smaller Android displays
class TrackBearingScreen extends StatefulWidget {
  final String? initialPayload;

  const TrackBearingScreen({
    super.key,
    this.initialPayload,
  });

  @override
  State<TrackBearingScreen> createState() => _TrackBearingScreenState();
}

class _TrackBearingScreenState extends State<TrackBearingScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  TrackViewStep _currentStep = TrackViewStep.landing;
  BearingTrackResult? _trackResult;
  MobileScannerController? _scannerController;
  late AnimationController _laserAnimController;

  bool _isTorchOn = false;
  bool _isCameraFacingBack = true;
  bool _cameraPermissionDenied = false;
  String? _lastScannedCode;
  final TextEditingController _manualInputController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  static const Color _greenPrimary = Color(0xFF0D8A4E);
  static const Color _greenBackground = Color(0xFFE8F5E9);
  static const Color _greenBorder = Color(0xFF2E7D32);
  static const Color _greenTextDark = Color(0xFF1B5E20);

  static const Color _redPrimary = Color(0xFFD32F2F);
  static const Color _redBackground = Color(0xFFFFEBEE);
  static const Color _redBorder = Color(0xFFC62828);
  static const Color _redTextDark = Color(0xFFB71C1C);

  final DateFormat _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

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
        _executeTracking(widget.initialPayload!);
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
    } else if (state == AppLifecycleState.resumed && _currentStep == TrackViewStep.scanner) {
      _scannerController?.start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _laserAnimController.dispose();
    _scannerController?.dispose();
    _manualInputController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _openScanner() {
    _initScanner();
    setState(() {
      _currentStep = TrackViewStep.scanner;
      _cameraPermissionDenied = false;
      _lastScannedCode = null;
    });
  }

  void _closeScanner() {
    _scannerController?.stop();
    setState(() {
      _currentStep = TrackViewStep.landing;
    });
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_currentStep != TrackViewStep.scanner) return;

    for (final barcode in capture.barcodes) {
      if (barcode.format != BarcodeFormat.qrCode) continue;
      final rawValue = barcode.rawValue?.trim();
      if (rawValue == null || rawValue.isEmpty) continue;
      if (rawValue == _lastScannedCode) continue;

      _lastScannedCode = rawValue;
      await _executeTracking(rawValue);
      break;
    }
  }

  Future<void> _executeTracking(String payload) async {
    setState(() {
      _currentStep = TrackViewStep.processing;
    });
    await _scannerController?.stop();

    try {
      final enteredNotes = _notesController.text.trim();
      final result = await BearingTrackService.trackScan(
        payload,
        notes: enteredNotes.isNotEmpty ? enteredNotes : null,
      );
      if (mounted) {
        setState(() {
          _trackResult = result;
          _currentStep = TrackViewStep.result;
        });

        // No auto-dialog for Track module — clean simple result only
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _trackResult = BearingTrackResult.invalid(
            rawPayload: payload,
            message: 'Tracking error: ${e.toString()}',
          );
          _currentStep = TrackViewStep.result;
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
              const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary),
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
                  'Scan or enter the bearing serial number. No photographs or uploads required.',
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
                    _buildTestChip('PB-9402-XJ', 'PB-9402-XJ'),
                    _buildTestChip('PB-8812-KR', 'PB-8812-KR'),
                    _buildSimulate5DaysChip('PB-9402-XJ', 'Simulate 5 Days In Use'),
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
                  _executeTracking(code);
                }
              },
              child: const Text('Track Scan'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTestChip(String value, String label) {
    return InkWell(
      onTap: () => _manualInputController.text = value,
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

  Widget _buildSimulate5DaysChip(String bearingId, String label) {
    return InkWell(
      onTap: () async {
        _manualInputController.text = bearingId;
        // Simulate an entry 5 days ago for demonstration
        await BearingTrackService.simulatePastEntryTime(bearingId, const Duration(days: 5));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Simulated: $bearingId was marked Bearing In 5 days ago!'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          border: Border.all(color: const Color(0xFFE65100), width: 1.0),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: const Color(0xFFE65100),
            fontSize: 11,
            fontWeight: FontWeight.bold,
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
        title: 'Track Your Bearing',
        onBack: () {
          if (_currentStep == TrackViewStep.scanner) {
            _closeScanner();
          } else if (_currentStep == TrackViewStep.result) {
            setState(() => _currentStep = TrackViewStep.landing);
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
      case TrackViewStep.landing:
        return _buildLandingView(constraints);
      case TrackViewStep.scanner:
        return _buildScannerView(constraints);
      case TrackViewStep.processing:
        return _buildProcessingView();
      case TrackViewStep.result:
        return _buildResultView(constraints);
    }
  }

  // ===========================================================================
  // 1. LANDING VIEW: Instant 1-Tap QR-Only Tracking
  // ===========================================================================
  Widget _buildLandingView(BoxConstraints constraints) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.gutterMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero Guide Card
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
                      Icons.sync_alt_rounded,
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
                  'Track Your Bearing',
                  style: AppTypography.headlineSm.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Effortlessly record when a bearing is installed (Bearing In) and removed (Bearing Out) by scanning its QR code. No photographs or image uploads required.',
                  style: AppTypography.bodySm.copyWith(
                    color: Colors.black87,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),
          const SizedBox(height: AppDimensions.spaceMd),

          // Primary CTA: Scan Bearing QR Code
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
                        'Scan Bearing QR to Track',
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

          // How Tracking Works Explainer
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
                Row(
                  children: [
                    const Icon(Icons.timeline_rounded, size: 20, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Automated IN / OUT Workflow',
                      style: AppTypography.labelMd.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildWorkflowStep(
                  stepNum: '1',
                  color: _greenPrimary,
                  title: '1st Scan: Bearing In',
                  description:
                      'Scanning a bearing not in use automatically logs entry date and time, displaying green Bearing In status and starting tracking.',
                ),
                const SizedBox(height: 10),
                _buildWorkflowStep(
                  stepNum: '2',
                  color: _redPrimary,
                  title: '2nd Scan: Bearing Out',
                  description:
                      'Scanning the bearing again while operating logs removal date and time, displaying red Bearing Out status and calculating total usage duration.',
                ),
                const SizedBox(height: 10),
                _buildWorkflowStep(
                  stepNum: '3',
                  color: _redPrimary,
                  title: 'One Cycle Only — Terminal',
                  description:
                      'Once marked Bearing Out, the bearing is permanently decommissioned. No re-installation or re-scanning is allowed.',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spaceMd),
        ],
      ),
    );
  }

  Widget _buildWorkflowStep({
    required String stepNum,
    required Color color,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
          ),
          child: Center(
            child: Text(
              stepNum,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: AppTypography.caption.copyWith(
                  color: Colors.black54,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 2. SCANNER VIEW: Instant QR Scanner Viewport
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
                  'Scan Bearing QR to Track',
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

              // Semi-transparent overlay with reticle cutout
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (ctx, box) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
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
                              ..._buildCornerBrackets(),
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
                              'POINT AT BEARING QR CODE',
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

        // Bottom Controls Bar
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
      Positioned(top: 0, left: 0, child: Container(width: length, height: thickness, color: cornerColor)),
      Positioned(top: 0, left: 0, child: Container(width: thickness, height: length, color: cornerColor)),
      Positioned(top: 0, right: 0, child: Container(width: length, height: thickness, color: cornerColor)),
      Positioned(top: 0, right: 0, child: Container(width: thickness, height: length, color: cornerColor)),
      Positioned(bottom: 0, left: 0, child: Container(width: length, height: thickness, color: cornerColor)),
      Positioned(bottom: 0, left: 0, child: Container(width: thickness, height: length, color: cornerColor)),
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
              'Please allow camera permission to scan bearing QR codes, or track by typing the serial number manually.',
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
  // 3. PROCESSING VIEW
  // ===========================================================================
  Widget _buildProcessingView() {
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
              'Updating Bearing Lifecycle...',
              style: AppTypography.headlineSm.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Recording entry or exit timestamp in authoritative registry...',
              style: AppTypography.caption.copyWith(color: Colors.black87),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 4. RESULT VIEW: Handles Bearing In (Green), Bearing Out (Red), and Invalid
  // ===========================================================================
  Widget _buildResultView(BoxConstraints constraints) {
    final result = _trackResult;
    if (result == null || result.isInvalid) {
      return _buildInvalidResultView(result);
    } else if (result.isAlreadyOut) {
      return _buildAlreadyOutView(result);
    } else if (result.isBearingIn) {
      return _buildBearingInResultView(result);
    } else {
      return _buildBearingOutResultView(result);
    }
  }

  // ---------------------------------------------------------------------------
  // A. BEARING IN: Prominent Green Status & Confirmation
  // ---------------------------------------------------------------------------
  Widget _buildBearingInResultView(BearingTrackResult result) {
    final inTimeFormatted = result.inTimestamp != null
        ? _dateFormat.format(result.inTimestamp!)
        : _dateFormat.format(DateTime.now());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.gutterMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Green Status Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _greenBackground,
              borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              border: Border.all(color: _greenBorder, width: 2.0),
              boxShadow: [
                BoxShadow(
                  color: _greenPrimary.withAlpha(25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _greenPrimary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3.0),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.login_rounded,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Green Status Pill: "Bearing In"
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: _greenPrimary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'BEARING IN',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  'Usage Tracking Started',
                  style: AppTypography.headlineSm.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    color: _greenTextDark,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Bearing installation entry timestamp recorded successfully.',
                  style: AppTypography.bodySm.copyWith(
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),

          // Installation Entry Details Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              border: Border.all(color: AppColors.primary, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'ENTRY RECORD',
                      style: AppTypography.labelMd.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _greenBackground,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _greenBorder, width: 1.0),
                      ),
                      child: Text(
                        'Cycle #${result.cycleNumber} Active',
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _greenTextDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.black12, height: 24),
                _buildSpecRow('Bearing In Date & Time', inTimeFormatted, isSuccess: true),
                _buildSpecRow('Status', 'Operating / In Use', isSuccess: true),
                if (_notesController.text.trim().isNotEmpty)
                  _buildSpecRow('Notes', _notesController.text.trim()),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),

          // Next Action Advisory Box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              border: Border.all(color: _greenBorder.withAlpha(80), width: 1.0),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: _greenPrimary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'When this bearing is removed from the machine, scan this QR code again to mark Bearing Out and view total usage duration.',
                    style: AppTypography.caption.copyWith(
                      color: _greenTextDark,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),

          // Actions
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
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
              style: AppTypography.labelMd.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: AppDimensions.spaceMd),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // B. BEARING OUT: Prominent Red Status, Usage Duration & Lifecycle Summary
  // ---------------------------------------------------------------------------
  Widget _buildBearingOutResultView(BearingTrackResult result) {
    final inTimeFormatted = result.inTimestamp != null
        ? _dateFormat.format(result.inTimestamp!)
        : 'N/A';
    final outTimeFormatted = result.outTimestamp != null
        ? _dateFormat.format(result.outTimestamp!)
        : _dateFormat.format(DateTime.now());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.gutterMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Red Status Card
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
                      Icons.logout_rounded,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Red Status Pill: "Bearing Out"
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: _redPrimary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.stop_circle_outlined, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'BEARING OUT',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Usage Duration (prominently displayed)
                Text(
                  result.formattedUsageDuration,
                  style: AppTypography.headlineSm.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: _redTextDark,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Bearing removal recorded. Completed cycle #${result.cycleNumber}.',
                  style: AppTypography.bodySm.copyWith(
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),

          // Lifecycle Details Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              border: Border.all(color: AppColors.primary, width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LIFECYCLE SUMMARY',
                  style: AppTypography.labelMd.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const Divider(color: Colors.black12, height: 24),
                _buildSpecRow('Bearing In Date & Time', inTimeFormatted),
                _buildSpecRow('Bearing Out Date & Time', outTimeFormatted, isDanger: true),
                _buildSpecRow(
                  'Total Usage Duration',
                  result.formattedUsageDuration.replaceAll('You used this bearing for ', '').replaceAll('.', ''),
                  isHighlighted: true,
                ),
                if (_notesController.text.trim().isNotEmpty)
                  _buildSpecRow('Notes', _notesController.text.trim()),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),

          // Terminal Notice
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _redBackground,
              borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              border: Border.all(color: _redBorder, width: 1.0),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.do_not_disturb_on_rounded, color: _redPrimary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This bearing has been permanently decommissioned. It cannot be scanned for Bearing In or Authentication again.',
                    style: AppTypography.caption.copyWith(
                      color: _redTextDark,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),

          // Send via WhatsApp Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: 2,
            ),
            onPressed: () => _shareViaWhatsApp(result),
            icon: const WhatsAppIcon(size: 22, color: Colors.white),
            label: Text(
              'Send via WhatsApp',
              style: AppTypography.labelMd.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.spaceSm),

          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
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
              style: AppTypography.labelMd.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: AppDimensions.spaceMd),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // B2. ALREADY OUT: Terminal — bearing permanently decommissioned, no re-scan
  // ---------------------------------------------------------------------------
  Widget _buildAlreadyOutView(BearingTrackResult result) {
    final inTimeStr = result.inTimestamp != null
        ? _dateFormat.format(result.inTimestamp!)
        : 'N/A';
    final outTimeStr = result.outTimestamp != null
        ? _dateFormat.format(result.outTimestamp!)
        : 'N/A';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.gutterMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Grey-Red Decommissioned Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5F5),
              borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              border: Border.all(color: _redBorder, width: 1.5),
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3.0),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.do_not_disturb_on_rounded,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'BEARING MARKED AS OUT',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Cannot scan again.',
                  style: AppTypography.headlineSm.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: Colors.grey[800],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'This bearing has been permanently decommissioned and cannot be scanned for Bearing In or Authentication.',
                  style: AppTypography.bodySm.copyWith(color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),

          // Last recorded lifecycle
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
                  'LAST RECORDED LIFECYCLE',
                  style: AppTypography.labelMd.copyWith(
                    fontWeight: FontWeight.w900,
                    color: Colors.grey[700],
                    letterSpacing: 0.5,
                  ),
                ),
                const Divider(color: Colors.black12, height: 24),
                if (result.inTimestamp != null)
                  _buildSpecRow('Bearing In', inTimeStr),
                if (result.outTimestamp != null)
                  _buildSpecRow('Bearing Out', outTimeStr, isDanger: true),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),

          // Send via WhatsApp Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: 2,
            ),
            onPressed: () => _shareViaWhatsApp(result),
            icon: const WhatsAppIcon(size: 22, color: Colors.white),
            label: Text(
              'Send via WhatsApp',
              style: AppTypography.labelMd.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.spaceSm),

          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
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
              style: AppTypography.labelMd.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: AppDimensions.spaceMd),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // C. INVALID CODE: Red Alert
  // ---------------------------------------------------------------------------
  Widget _buildInvalidResultView(BearingTrackResult? result) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.gutterMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _redBackground,
              borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              border: Border.all(color: _redBorder, width: 2.0),
            ),
            child: Column(
              children: [
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
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
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
                Text(
                  'Bearing Authenticity Could Not Be Verified',
                  style: AppTypography.labelMd.copyWith(
                    color: _redPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'The scanned QR code does not match any registered bearing record. Only valid Pivot Bearings India QR codes can be tracked.',
                  style: AppTypography.bodySm.copyWith(color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: AppDimensions.spaceMd),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _openScanner,
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
            label: Text(
              'Try Scanning Again',
              style: AppTypography.labelMd.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.spaceSm),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
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
              style: AppTypography.labelMd.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: AppDimensions.spaceMd),
        ],
      ),
    );
  }

  Widget _buildSpecRow(
    String label,
    String value, {
    bool isHighlighted = false,
    bool isSuccess = false,
    bool isDanger = false,
  }) {
    Color valColor = Colors.black87;
    if (isHighlighted) valColor = AppColors.primary;
    if (isSuccess) valColor = _greenTextDark;
    if (isDanger) valColor = _redTextDark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTypography.bodySm.copyWith(
                fontWeight: (isHighlighted || isSuccess || isDanger)
                    ? FontWeight.w800
                    : FontWeight.w600,
                color: valColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareViaWhatsApp(BearingTrackResult result) async {
    final inTimeFormatted = result.inTimestamp != null
        ? _dateFormat.format(result.inTimestamp!)
        : 'N/A';
    final outTimeFormatted = result.outTimestamp != null
        ? _dateFormat.format(result.outTimestamp!)
        : _dateFormat.format(DateTime.now());
    final durationClean = result.formattedUsageDuration
        .replaceAll('You used this bearing for ', '')
        .replaceAll('.', '');

    final auth = AuthController.instance;
    final prefs = await SharedPreferences.getInstance();
    final storedNotes = (result.notes != null && result.notes!.trim().isNotEmpty)
        ? result.notes!.trim()
        : (prefs.getString('pbi_bearing_notes_${result.bearingId}') ??
            prefs.getString('pbi_bearing_notes_${result.rawPayload}') ??
            '');
    final notesLine = (storedNotes.isNotEmpty) ? '\n• *Notes:* $storedNotes' : '';

    final message = '''
*PIVOT BEARINGS INDIA - BEARING LIFECYCLE SUMMARY*
━━━━━━━━━━━━━━━━━━━━━━━━━
• *Bearing ID:* ${result.bearingId ?? 'N/A'}
• *Model Number:* ${result.modelNumber ?? 'PBI-6204-ZZ'}
• *Bearing In:* $inTimeFormatted
• *Bearing Out:* $outTimeFormatted
• *Total Usage Duration:* $durationClean
• *Completed Cycle:* Cycle #${result.cycleNumber} Closed
• *Status:* Decommissioned / Bearing Out$notesLine
━━━━━━━━━━━━━━━━━━━━━━━━━
Authorized Bearing Usage Telemetry
'''.trim();

    String? authNumber;
    if (auth.authorisedNumbers.isNotEmpty) {
      authNumber = auth.authorisedNumbers.first;
    } else {
      authNumber = prefs.getString('pbi_authorised_number');
    }

    if (authNumber != null && authNumber.trim().isNotEmpty) {
      var cleanNum = authNumber.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanNum.length == 10) cleanNum = '91$cleanNum';
      final uri = Uri.parse('https://wa.me/$cleanNum?text=${Uri.encodeComponent(message)}');
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open WhatsApp: $e')),
          );
        }
      }
    } else {
      _showWhatsAppNumberDialog(message);
    }
  }

  void _showWhatsAppNumberDialog(String message) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
          side: const BorderSide(color: Color(0xFF25D366), width: 2.0),
        ),
        title: Row(
          children: const [
            Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 24),
            SizedBox(width: 8),
            Text(
              'Send via WhatsApp',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the Authorised Person Mobile Number to send this bearing lifecycle summary:',
              style: AppTypography.bodySm,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Authorised Mobile Number',
                hintText: 'e.g. +91 98988 57198',
                prefixIcon: const Icon(Icons.phone, color: Color(0xFF25D366)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final raw = controller.text.trim();
              Navigator.pop(ctx);
              var cleanNum = raw.replaceAll(RegExp(r'[^0-9]'), '');
              if (cleanNum.length == 10) cleanNum = '91$cleanNum';
              final uri = cleanNum.isNotEmpty
                  ? Uri.parse('https://wa.me/$cleanNum?text=${Uri.encodeComponent(message)}')
                  : Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}');
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            },
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Send on WhatsApp'),
          ),
        ],
      ),
    );
  }
}
