import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../../../core/widgets/industrial_status_badge.dart';
import '../../../../core/widgets/app_snack_bar.dart';

import '../../data/models/bearing_model.dart';
import '../../data/repositories/bearing_repository.dart';
import '../../../qr_generation/data/repositories/qr_management_repository.dart';
import '../../domain/services/warranty_calculator.dart';

class OutConfirmationScreen extends StatefulWidget {
  final String bearingId;

  const OutConfirmationScreen({super.key, required this.bearingId});

  @override
  State<OutConfirmationScreen> createState() => _OutConfirmationScreenState();
}

class _OutConfirmationScreenState extends State<OutConfirmationScreen> {
  BearingModel? _bearing;
  bool _isProcessing = false;
  Timer? _liveTicker;

  @override
  void initState() {
    super.initState();
    _loadBearing();
    _liveTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _liveTicker?.cancel();
    super.dispose();
  }

  Future<void> _loadBearing() async {
    await QrManagementRepository.loadFromLocalStorage();
    final b = await BearingRepositoryImpl().getBearingById(widget.bearingId);

    // AUTO-MODE: If bearing was never marked IN, auto-switch to Mark Bearing IN
    if (b?.state == BearingLifecycleState.notActivated) {
      if (mounted) {
        AppSnackBar.showInfo(
          context,
          'Bearing is not marked IN yet. Automatically switched to Mark Bearing IN.',
        );
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.inConfirmation,
          arguments: widget.bearingId,
        );
        return;
      }
    }

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

  String _formatOperatingDuration(Duration d) {
    final totalSec = d.inSeconds;
    if (totalSec < 0) return '0 Secs';
    if (totalSec < 60) {
      return '$totalSec ${totalSec == 1 ? "Sec" : "Secs"}';
    }
    final totalMin = d.inMinutes;
    final remSec = totalSec % 60;
    if (totalMin < 60) {
      if (remSec == 0) return '$totalMin ${totalMin == 1 ? "Min" : "Mins"}';
      return '$totalMin ${totalMin == 1 ? "Min" : "Mins"}, $remSec ${remSec == 1 ? "Sec" : "Secs"}';
    }
    final totalHours = d.inHours;
    final remMin = totalMin % 60;
    if (totalHours < 24) {
      if (remSec == 0) return '$totalHours ${totalHours == 1 ? "Hour" : "Hours"}, $remMin ${remMin == 1 ? "Min" : "Mins"}';
      return '$totalHours ${totalHours == 1 ? "Hour" : "Hours"}, $remMin ${remMin == 1 ? "Min" : "Mins"}, $remSec ${remSec == 1 ? "Sec" : "Secs"}';
    }
    final days = d.inDays;
    final remHours = totalHours % 24;
    return '$days ${days == 1 ? "Day" : "Days"}, $remHours ${remHours == 1 ? "Hour" : "Hours"}, $remMin ${remMin == 1 ? "Min" : "Mins"}, $remSec ${remSec == 1 ? "Sec" : "Secs"}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final inDate = _bearing?.lastInDate ?? _bearing?.firstInDate;
    final inTimeStr = inDate != null
        ? '${_formatDate(inDate)}, ${inDate.hour.toString().padLeft(2, '0')}:${inDate.minute.toString().padLeft(2, '0')}'
        : 'Session Recorded';
    
    final durationMonths = _bearing?.warrantyDurationMonths ?? 0;
    DateTime? expiry = _bearing?.warrantyExpiryDate;
    if (inDate != null && durationMonths > 0) {
      expiry = WarrantyCalculator.calculateExpiryDate(firstInDate: inDate, durationMonths: durationMonths);
    }
    final isWarrantyValid = expiry != null ? expiry.isAfter(now) : !(_bearing?.isWarrantyExpired ?? false);
    final expiryStr = _formatDate(expiry);

    final durationUsed = inDate != null ? now.difference(inDate) : Duration.zero;
    final operatingDurationStr = inDate != null ? _formatOperatingDuration(durationUsed) : 'Calculating...';

    final daysRemaining = expiry?.difference(now).inDays;
    final remainingWarrantyStr = daysRemaining != null
        ? (daysRemaining > 0 ? '$daysRemaining Days Remaining' : '0 Days (Expired)')
        : 'Active Coverage';

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
                    _buildRow('Operating Duration So Far', operatingDurationStr, isHeadline: true),
                    _buildRow('Warranty Duration', durationMonths > 0 ? '$durationMonths Months' : 'Under Assessment'),
                    _buildRow('Warranty Expiry Date', expiryStr),
                    _buildRow('Warranty Remaining So Far', remainingWarrantyStr),
                    _buildRow('Active Warranty Status', '${isWarrantyValid ? "Valid" : "Expired"} ($durationMonths Months)'),
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
                    const SizedBox(height: 6),
                    const Text(
                      'Marking OUT preserves all historical telemetry and will calculate total cumulative operating duration.',
                      style: AppTypography.bodySm,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.spaceLg),

              // Confirm Button
              IndustrialButton(
                label: 'CONFIRM MARK BEARING OUT',
                icon: Icons.output_rounded,
                width: double.infinity,
                variant: IndustrialButtonVariant.danger,
                isLoading: _isProcessing,
                onPressed: _confirmAndMarkOut,
              ),

              const SizedBox(height: AppDimensions.spaceSm),

              // Cancel Button
              IndustrialButton(
                label: 'Cancel',
                width: double.infinity,
                variant: IndustrialButtonVariant.secondary,
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isHeadline = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.bodyMd),
          Text(
            value,
            style: isHeadline
                ? AppTypography.bodyMd.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary)
                : AppTypography.bodyMd.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
