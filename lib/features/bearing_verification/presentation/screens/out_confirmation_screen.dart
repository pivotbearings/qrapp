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

class OutConfirmationScreen extends StatefulWidget {
  final String bearingId;

  const OutConfirmationScreen({super.key, required this.bearingId});

  @override
  State<OutConfirmationScreen> createState() => _OutConfirmationScreenState();
}

class _OutConfirmationScreenState extends State<OutConfirmationScreen> {
  BearingModel? _bearing;
  bool _isProcessing = false;

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

  Future<void> _confirmAndMarkOut() async {
    if (_isProcessing) return; // Prevent duplicate clicks!
    setState(() => _isProcessing = true);

    try {
      await BearingRepositoryImpl().markBearingOut(widget.bearingId);
      if (!mounted) return;

      Navigator.pushReplacementNamed(
        context,
        AppRoutes.outResult,
        arguments: widget.bearingId,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to mark OUT: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final inDate = _bearing?.lastInDate ?? _bearing?.firstInDate;
    final inTimeStr = inDate != null
        ? '${_formatDate(inDate)}, ${inDate.hour.toString().padLeft(2, '0')}:${inDate.minute.toString().padLeft(2, '0')}'
        : 'Session Recorded';
    final durationMonths = _bearing?.warrantyDurationMonths ?? 6;
    final isWarrantyValid = !(_bearing?.isWarrantyExpired ?? false);
    final expiryStr = _formatDate(_bearing?.warrantyExpiryDate);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const IndustrialAppBar(title: 'Bearing Lifecycle'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.gutterMobile),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Mark Bearing OUT', style: AppTypography.headlineLgMobile),
              const SizedBox(height: AppDimensions.spaceMd),

              // Installation Status Card
              IndustrialCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(widget.bearingId, style: AppTypography.headlineSm),
                        const IndustrialStatusBadge(statusText: '[STATUS: CURRENTLY IN]'),
                      ],
                    ),
                    const Divider(),
                    _buildRow('Installation Status', 'CURRENTLY IN'),
                    _buildRow('Original IN Date & Time', inTimeStr),
                    _buildRow('Active Warranty Status', '${isWarrantyValid ? "Valid" : "Expired"} ($durationMonths Months)'),
                    _buildRow('Warranty Expiry Date', expiryStr),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.spaceMd),

              // Operational Protocol Notice Box
              IndustrialCard(
                padding: const EdgeInsets.all(AppDimensions.spaceMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info, color: AppColors.primary, size: 20),
                        SizedBox(width: 8),
                        Text('Operational Protocol Notice', style: AppTypography.headlineSm),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.spaceSm),
                    const Text(
                      'Confirming OUT will record the authoritative server removal timestamp, close the current operational cycle, and mark this bearing as decommissioned. Instant, seamless checkout with zero camera delay.',
                      style: AppTypography.bodyMd,
                    ),
                    const SizedBox(height: AppDimensions.spaceSm),
                    const Text(
                      'Marking OUT preserves all historical telemetry and will calculate total cumulative operating duration.',
                      style: AppTypography.bodyMd,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.spaceLg),

              // Quick & Seamless 1-Tap OUT (No image capture asked, duplicate click protected)
              IndustrialButton.danger(
                label: _isProcessing ? 'MARKING OUT...' : 'CONFIRM MARK BEARING OUT',
                icon: Icons.logout,
                isLoading: _isProcessing,
                onPressed: _isProcessing ? null : _confirmAndMarkOut,
              ),

              const SizedBox(height: AppDimensions.spaceSm),

              IndustrialButton.secondary(
                label: 'Cancel',
                onPressed: _isProcessing ? null : () => Navigator.pop(context),
              ),
              const SizedBox(height: AppDimensions.spaceXl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.labelSm),
          Text(value, style: AppTypography.labelMd),
        ],
      ),
    );
  }
}
