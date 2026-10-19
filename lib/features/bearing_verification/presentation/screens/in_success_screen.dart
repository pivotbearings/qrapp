import 'package:flutter/material.dart';
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
import '../../domain/services/warranty_calculator.dart';

class InSuccessScreen extends StatefulWidget {
  final String bearingId;

  const InSuccessScreen({super.key, required this.bearingId});

  @override
  State<InSuccessScreen> createState() => _InSuccessScreenState();
}

class _InSuccessScreenState extends State<InSuccessScreen> {
  BearingModel? _bearing;

  @override
  void initState() {
    super.initState();
    _loadBearing();
  }

  Future<void> _loadBearing() async {
    final b = await BearingRepositoryImpl().getBearingById(widget.bearingId);
    if (mounted) {
      setState(() {
        _bearing = b;
      });
    }
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final durationMonths = _bearing?.warrantyDurationMonths ?? 6;
    final expiry = _bearing?.warrantyExpiryDate ??
        WarrantyCalculator.calculateExpiryDate(firstInDate: now, durationMonths: durationMonths);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const IndustrialAppBar(title: 'Mark IN Complete'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.gutterMobile),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // All Steps Completed Banner (1. Scan -> 2. Photo -> 3. Active)
              _buildCompletedStepper(),

              const SizedBox(height: AppDimensions.spaceMd),

              // Hero Success Card
              IndustrialCard(
                padding: const EdgeInsets.all(AppDimensions.spaceLg),
                child: Center(
                  child: Column(
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFDCFCE7),
                          border: Border.all(color: const Color(0xFF16A34A), width: 2.5),
                        ),
                        child: const Center(
                          child: Icon(Icons.verified_rounded, size: 44, color: Color(0xFF16A34A)),
                        ),
                      ),
                      const SizedBox(height: AppDimensions.spaceMd),
                      Text(
                        'Bearing Marked IN!',
                        style: AppTypography.headlineSm.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Photo proof submitted & warranty activated.',
                        style: AppTypography.bodySm.copyWith(color: Colors.black87),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppDimensions.spaceMd),
                      const IndustrialStatusBadge(
                        statusText: 'WARRANTY ACTIVE',
                        icon: Icons.shield,
                        isSuccess: true,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppDimensions.spaceMd),

              // Warranty & Inspection Certificate Card
              IndustrialCard(
                padding: const EdgeInsets.all(AppDimensions.spaceMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified_outlined, size: 20, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          'WARRANTY REGISTRY DETAILS',
                          style: AppTypography.labelMd.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _buildInfoRow(
                      icon: Icons.fingerprint,
                      label: 'Bearing Identifier',
                      value: widget.bearingId,
                      isBold: true,
                    ),
                    const SizedBox(height: 10),
                    _buildInfoRow(
                      icon: Icons.calendar_today_outlined,
                      label: 'Installation (IN) Date',
                      value: _formatDate(now),
                    ),
                    const SizedBox(height: 10),
                    _buildInfoRow(
                      icon: Icons.shield_outlined,
                      label: 'Warranty Expiry Date',
                      value: _formatDate(expiry),
                      highlightGreen: true,
                    ),
                    const SizedBox(height: 10),
                    _buildInfoRow(
                      icon: Icons.cloud_done_outlined,
                      label: 'Optical Evidence Proof',
                      value: 'Recorded & Cloud Secured',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.spaceMd),

              // Reassurance Callout
              Container(
                padding: const EdgeInsets.all(AppDimensions.spaceSm + 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                  border: Border.all(color: const Color(0xFF86EFAC), width: 1.0),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF16A34A), size: 22),
                    const SizedBox(width: AppDimensions.spaceSm),
                    Expanded(
                      child: Text(
                        'You can view this bearing and track warranty status anytime under "Warranty Check".',
                        style: AppTypography.caption.copyWith(color: const Color(0xFF166534)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.spaceLg),

              // Action Buttons
              IndustrialButton(
                label: 'Return to Dashboard',
                icon: Icons.home_rounded,
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  AppRoutes.customerHome,
                  (route) => false,
                ),
              ),

              const SizedBox(height: AppDimensions.spaceSm),

              IndustrialButton.secondary(
                label: 'Scan Another Bearing',
                icon: Icons.qr_code_scanner_rounded,
                onPressed: () => Navigator.pushReplacementNamed(context, AppRoutes.qrScanner),
              ),

              const SizedBox(height: AppDimensions.spaceXl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompletedStepper() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        border: Border.all(color: const Color(0xFF86EFAC), width: 1.2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildDoneStep(label: '1. Scanned', icon: Icons.qr_code_2_rounded),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFF16A34A)),
          const SizedBox(width: 8),
          _buildDoneStep(label: '2. Photo Proof', icon: Icons.camera_alt_rounded),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFF16A34A)),
          const SizedBox(width: 8),
          _buildDoneStep(label: '3. Active', icon: Icons.verified_user_rounded),
        ],
      ),
    );
  }

  Widget _buildDoneStep({required String label, required IconData icon}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF16A34A)),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTypography.caption.copyWith(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF166534),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    bool isBold = false,
    bool highlightGreen = false,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: highlightGreen ? const Color(0xFF16A34A) : AppColors.primary,
        ),
        const SizedBox(width: 8),
        Text(label, style: AppTypography.bodyMd),
        const Spacer(),
        Text(
          value,
          style: AppTypography.labelMd.copyWith(
            fontWeight: isBold || highlightGreen ? FontWeight.bold : FontWeight.w600,
            color: highlightGreen ? const Color(0xFF16A34A) : AppColors.primary,
          ),
        ),
      ],
    );
  }
}
