import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../../../core/widgets/industrial_status_badge.dart';

import '../../data/models/bearing_model.dart';
import '../../data/repositories/bearing_repository.dart';

class InConfirmationScreen extends StatefulWidget {
  final String bearingId;

  const InConfirmationScreen({super.key, required this.bearingId});

  @override
  State<InConfirmationScreen> createState() => _InConfirmationScreenState();
}

class _InConfirmationScreenState extends State<InConfirmationScreen> {
  BearingModel? _bearing;
  bool _isLoading = true;
  bool _isPermanentlyOut = false;

  @override
  void initState() {
    super.initState();
    _loadBearing();
  }

  Future<void> _loadBearing() async {
    final cleanId = widget.bearingId.trim().toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    final isOutLocally = prefs.getBool('pbi_bearing_permanently_out_$cleanId') == true ||
        prefs.getString('pbi_track_state_$cleanId') == 'FINAL_OUT' ||
        prefs.getString('pbi_bearing_state_$cleanId') == 'CURRENTLY_OUT';

    final b = await BearingRepositoryImpl().getBearingById(cleanId);
    final isOut = isOutLocally || b?.state == BearingLifecycleState.currentlyOut;

    if (mounted) {
      setState(() {
        _bearing = b;
        _isPermanentlyOut = isOut;
        _isLoading = false;
      });
    }
  }

  void _confirmAndStartWarranty() {
    if (_isPermanentlyOut) return;
    Navigator.pushNamed(
      context,
      AppRoutes.inVerificationCapture,
      arguments: widget.bearingId,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isPermanentlyOut) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: const IndustrialAppBar(title: 'Mark Bearing IN'),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppDimensions.gutterMobile),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Red Decommissioned Hero Alert
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                        border: Border.all(color: const Color(0xFFDC2626), width: 1.5),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: const BoxDecoration(
                              color: Color(0xFFDC2626),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.do_not_disturb_on_rounded,
                                size: 36,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'BEARING MARKED AS OUT',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Cannot scan again.',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF991B1B),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'This bearing has been permanently decommissioned and cannot be scanned for Bearing In or Authentication.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.black87,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spaceMd),

                    // Last Recorded Specs Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'BEARING DETAILS',
                            style: AppTypography.labelMd.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          const Divider(color: Colors.black12, height: 20),
                          _buildSpecRow('Bearing Serial', widget.bearingId),
                          const SizedBox(height: 8),
                          _buildSpecRow('Model / Type', _bearing?.modelNumber ?? 'PBI-6204-ZZ'),
                          const SizedBox(height: 8),
                          _buildSpecRow('Batch Code', _bearing?.batchCode ?? 'BATCH-ACTIVE'),
                          const SizedBox(height: 8),
                          _buildSpecRow('Status', 'DECOMMISSIONED', isDanger: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spaceLg),

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
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final durationMonths = _bearing?.warrantyDurationMonths ?? 6;
    final modelName = _bearing?.modelNumber ?? 'Standard Industrial Bearing';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const IndustrialAppBar(title: 'Mark Bearing IN'),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.0),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppDimensions.gutterMobile),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Page Heading
                        Text(
                          'Mark Bearing IN',
                          style: AppTypography.headlineLgMobile.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Review bearing details and proceed to optical evidence capture.',
                          style: AppTypography.bodyMd.copyWith(
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppDimensions.spaceMd),

                        // Bearing Specifications Card
                        IndustrialCard(
                          padding: const EdgeInsets.all(AppDimensions.spaceMd),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'BEARING SERIAL',
                                          style: AppTypography.caption.copyWith(
                                            letterSpacing: 0.8,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          widget.bearingId,
                                          style: AppTypography.headlineSm.copyWith(
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const IndustrialStatusBadge(
                                    statusText: 'VERIFIED',
                                    icon: Icons.check_circle_outline,
                                    isSuccess: true,
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              _buildSpecRow('Model / Type', modelName),
                              const SizedBox(height: 8),
                              _buildSpecRow('Warranty Coverage', '$durationMonths Months'),
                              const SizedBox(height: 8),
                              _buildSpecRow('Protocol Standard', 'ISO Precision Certified'),
                            ],
                          ),
                        ),

                        const SizedBox(height: AppDimensions.spaceMd),

                        // Minimalist 3-Step Linear Process (Clean, Perfectly Centered)
                        IndustrialCard(
                          padding: const EdgeInsets.all(AppDimensions.spaceMd),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ACTIVATION PROCESS',
                                style: AppTypography.labelMd.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: AppDimensions.spaceMd),
                              _buildStepRow(
                                stepNumber: '1',
                                icon: Icons.check,
                                title: 'QR Authenticated',
                                description: 'Bearing verified in registry',
                                isDone: true,
                              ),
                              const Divider(height: 20),
                              _buildStepRow(
                                stepNumber: '2',
                                icon: Icons.camera_alt_rounded,
                                title: 'Capture Photo Proof',
                                description: 'Take photo of bearing in position',
                                isActive: true,
                              ),
                              const Divider(height: 20),
                              _buildStepRow(
                                stepNumber: '3',
                                icon: Icons.shield_outlined,
                                title: 'Warranty Activated',
                                description: '$durationMonths-month coverage starts immediately',
                                isMuted: true,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: AppDimensions.spaceMd),

                        // Concise guidance note
                        Row(
                          children: [
                            const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Ensure bearing laser markings are visible in the photo.',
                                style: AppTypography.caption.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: AppDimensions.spaceLg),

                        // Action Buttons
                        IndustrialButton.success(
                          label: 'OPEN CAMERA & SUBMIT IN',
                          icon: Icons.camera_alt_rounded,
                          onPressed: _confirmAndStartWarranty,
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
              ),
      ),
    );
  }

  Widget _buildSpecRow(String label, String value, {bool isDanger = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.bodyMd.copyWith(
            fontWeight: FontWeight.w600,
            color: isDanger ? const Color(0xFFDC2626) : AppColors.primary,
          ),
        ),
        Text(
          value,
          style: AppTypography.bodyMd.copyWith(
            fontWeight: FontWeight.bold,
            color: isDanger ? const Color(0xFFDC2626) : AppColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildStepRow({
    required String stepNumber,
    required IconData icon,
    required String title,
    required String description,
    bool isDone = false,
    bool isActive = false,
    bool isMuted = false,
  }) {
    final Color badgeColor = isDone
        ? const Color(0xFF16A34A)
        : (isActive ? AppColors.primary : Colors.black26);

    final Color badgeBg = isDone
        ? const Color(0xFFDCFCE7)
        : (isActive ? AppColors.primary : Colors.transparent);

    final Color iconColor = isDone
        ? const Color(0xFF16A34A)
        : (isActive ? Colors.white : Colors.black45);

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: badgeBg,
            border: Border.all(color: badgeColor, width: 1.5),
          ),
          child: Center(
            child: Icon(icon, size: 16, color: iconColor),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.bodyMd.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isMuted ? Colors.black54 : AppColors.primary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                description,
                style: AppTypography.caption.copyWith(
                  color: isMuted ? Colors.black45 : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (isDone)
          const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF16A34A))
        else if (isActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'NEXT',
              style: AppTypography.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ),
      ],
    );
  }
}
