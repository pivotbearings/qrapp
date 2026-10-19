import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../../../core/widgets/industrial_status_badge.dart';
import '../../data/models/bearing_model.dart';
import '../../data/repositories/bearing_repository.dart';
import '../../domain/services/warranty_calculator.dart';

class BearingVerificationScreen extends StatefulWidget {
  final String bearingId;

  const BearingVerificationScreen({
    super.key,
    required this.bearingId,
  });

  @override
  State<BearingVerificationScreen> createState() =>
      _BearingVerificationScreenState();
}

class _BearingVerificationScreenState extends State<BearingVerificationScreen> {
  final BearingRepository _repository = BearingRepositoryImpl();
  BearingModel? _bearing;
  List<Map<String, dynamic>> _lifecycleHistory = [];
  Map<String, dynamic>? _companySettings;

  bool _isLoading = true;
  bool _isNavigating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBearingAndHistory();
  }

  Future<void> _loadBearingAndHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final b = await _repository.getBearingById(widget.bearingId);
      final history = await SupabaseService.fetchBearingHistory(widget.bearingId);
      final company = await SupabaseService.fetchCompanySettings();

      if (mounted) {
        setState(() {
          _bearing = b;
          _lifecycleHistory = history;
          _companySettings = company;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _onConfirmInPressed() {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    Navigator.pushNamed(
      context,
      AppRoutes.inConfirmation,
      arguments: widget.bearingId,
    ).then((_) {
      if (mounted) setState(() => _isNavigating = false);
    });
  }


  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: IndustrialAppBar(title: loc.translate('optical_verification')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.0),
              const SizedBox(height: AppDimensions.spaceMd),
              Text(loc.translate('loading'), style: AppTypography.caption),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: IndustrialAppBar(title: loc.translate('optical_verification')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppDimensions.gutterMobile),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.primary),
                const SizedBox(height: AppDimensions.spaceMd),
                Text(loc.translate('network_error'), style: AppTypography.headlineSm),
                const SizedBox(height: AppDimensions.spaceSm),
                Text(_errorMessage!, style: AppTypography.bodySm, textAlign: TextAlign.center),
                const SizedBox(height: AppDimensions.spaceLg),
                IndustrialButton(
                  label: 'RETRY CONNECTION',
                  onPressed: _loadBearingAndHistory,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bearing = _bearing!;
    final isNotActivated = bearing.state == BearingLifecycleState.notActivated;
    final isCurrentlyIn = bearing.state == BearingLifecycleState.currentlyIn;
    final isCurrentlyOut = bearing.state == BearingLifecycleState.currentlyOut;
    final isExpired = bearing.isWarrantyExpired;

    // Calculate dynamic operating duration
    String operatingDurationStr = 'N/A';
    if (bearing.firstInDate != null) {
      if (isCurrentlyIn && bearing.lastInDate != null) {
        final duration = WarrantyCalculator.calculateOperatingDuration(
          inTimestamp: bearing.lastInDate!,
          outTimestamp: DateTime.now(),
        );
        operatingDurationStr = WarrantyCalculator.formatOperatingDuration(duration);
      } else if (isCurrentlyOut && bearing.lastInDate != null && bearing.lastOutDate != null) {
        final duration = WarrantyCalculator.calculateOperatingDuration(
          inTimestamp: bearing.lastInDate!,
          outTimestamp: bearing.lastOutDate!,
        );
        operatingDurationStr = WarrantyCalculator.formatOperatingDuration(duration);
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: IndustrialAppBar(title: loc.translate('optical_verification')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDimensions.gutterMobile),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              // Company Header Chip (Dynamic from Supabase)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 1.0),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${_companySettings?['company_name'] ?? 'Pivot Bearings India'} • GSTIN: ${_companySettings?['gst_number'] ?? '27AABCP1234F1ZQ'}',
                        style: AppTypography.caption.copyWith(fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.shield_outlined, size: 14, color: AppColors.primary),
                  ],
                ),
              ),
              const SizedBox(height: AppDimensions.spaceSm),

              Text(
                loc.translate('optical_verification'),
                style: AppTypography.headlineLgMobile,
              ),
              const SizedBox(height: AppDimensions.spaceMd),

              // Status Indicator Hero Card
              IndustrialCard(
                padding: const EdgeInsets.all(AppDimensions.spaceLg),
                child: Center(
                  child: Column(
                    children: [
                      // Mechanical Bearing Stamp Icon
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary, width: 2.5),
                        ),
                        child: const Center(
                          child: Icon(Icons.check, size: 32, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: AppDimensions.spaceMd),
                      Text(
                        loc.translate('bearing_verified'),
                        style: AppTypography.headlineSm,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        isNotActivated
                            ? 'Not Installed (Ready for First IN)'
                            : (isCurrentlyIn ? loc.translate('currently_in') : loc.translate('currently_out')),
                        style: AppTypography.bodyMd,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppDimensions.spaceMd),

                      // Understandable State Badges Row
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8.0,
                        runSpacing: 6.0,
                        children: [
                          IndustrialStatusBadge(
                            statusText: isCurrentlyIn ? loc.translate('currently_in') : (isCurrentlyOut ? loc.translate('currently_out') : 'NOT ACTIVATED'),
                            icon: Icons.settings,
                          ),
                          IndustrialStatusBadge(
                            statusText: isNotActivated
                                ? 'WARRANTY PENDING FIRST IN'
                                : (isExpired ? loc.translate('warranty_expired').toUpperCase() : loc.translate('warranty_active').toUpperCase()),
                            icon: isExpired ? Icons.warning_amber_rounded : Icons.verified_user_outlined,
                            isDanger: isExpired,
                            isSuccess: !isExpired && !isNotActivated,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppDimensions.spaceMd),

              // Specifications & Authoritative Lifecycle Card
              IndustrialCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Telemetry & Warranty Horizon', style: AppTypography.labelLg),
                    const SizedBox(height: AppDimensions.spaceMd),
                    _buildSpecRow(loc.translate('bearing_id'), bearing.id, isMono: true),
                    _buildSpecRow(loc.translate('batch_code'), bearing.batchCode, isMono: true),
                    _buildSpecRow(loc.translate('warranty_period'), '${bearing.warrantyDurationMonths} Months'),
                    _buildSpecRow(
                      'First IN (Activation)',
                      bearing.firstInDate != null
                          ? bearing.firstInDate!.toLocal().toString().split('.')[0]
                          : 'Not Activated (Starts on First IN)',
                    ),
                    _buildSpecRow(
                      loc.translate('expiry_date'),
                      bearing.warrantyExpiryDate != null
                          ? '${bearing.warrantyExpiryDate!.toLocal().toString().split(' ')[0]} ${isExpired ? "[EXPIRED]" : "[ACTIVE]"}'
                          : 'Pending First IN',
                      isHighlightDanger: isExpired,
                    ),
                    _buildSpecRow(
                      loc.translate('installation_duration'),
                      operatingDurationStr,
                      isMono: true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.spaceMd),

              // Relevant Lifecycle History Card
              IndustrialCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(loc.translate('lifecycle_history'), style: AppTypography.labelLg),
                        const Icon(Icons.history, size: 18, color: AppColors.primary),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.spaceSm),
                    if (_lifecycleHistory.isEmpty)
                      Text(
                        isNotActivated
                            ? 'No lifecycle history yet. Installation starts upon confirming IN.'
                            : 'Historical events recorded in authoritative PostgreSQL registry.',
                        style: AppTypography.caption,
                      )
                    else
                      Column(
                        children: _lifecycleHistory.take(5).map((evt) {
                          final eventType = evt['event_type'] ?? 'EVENT';
                          final timestamp = evt['server_timestamp']?.toString().split('.')[0] ?? 'N/A';
                          final imgMap = evt['verification_images'] as Map<String, dynamic>?;
                          final hash = imgMap?['sha256_hash'] ?? 'N/A';

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.primary, width: 1.0),
                              borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('[$eventType]', style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                                    Text(timestamp, style: AppTypography.caption),
                                  ],
                                ),
                                if (hash != 'N/A') ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'HASH: ${hash.length > 28 ? "${hash.substring(0, 28)}..." : hash}',
                                    style: AppTypography.caption.copyWith(fontSize: 10),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.spaceMd),

              // Business Rule Notice Box (Clear & Friendly Guidance)
              IndustrialCard(
                padding: const EdgeInsets.all(AppDimensions.spaceMd),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isNotActivated
                          ? Icons.camera_alt_outlined
                          : (isCurrentlyIn ? Icons.logout_rounded : Icons.info_outline),
                      color: isNotActivated ? const Color(0xFF16A34A) : AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: AppDimensions.spaceSm),
                    Expanded(
                      child: Text(
                        isCurrentlyOut
                            ? 'This bearing has been marked OUT and decommissioned. Its lifecycle is permanently closed.'
                            : (isNotActivated
                                ? 'Ready to install? Tap "MARK BEARING IN & SUBMIT" below to snap a quick photo proof and activate 6 months of official warranty.'
                                : 'Physical QR scanning required: To mark this bearing OUT, scan its physical QR code on the machine to confirm removal and capture evidence.'),
                        style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.spaceLg),

              // Action Buttons with Double-Tap Guard (Green for IN, Red for OUT - Scan Required)
              if (isNotActivated)
                IndustrialButton.success(
                  label: 'MARK BEARING IN & SUBMIT',
                  icon: Icons.login,
                  isLoading: _isNavigating,
                  onPressed: _onConfirmInPressed,
                )
              else if (isCurrentlyIn)
                IndustrialButton.danger(
                  label: 'SCAN QR TO MARK BEARING OUT',
                  icon: Icons.qr_code_scanner,
                  isLoading: _isNavigating,
                  onPressed: () => Navigator.pushReplacementNamed(context, AppRoutes.qrScanner),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppDimensions.spaceMd),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    border: Border.all(color: AppColors.primary, width: 2.0),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.do_not_disturb_on_outlined, size: 28, color: AppColors.primary),
                      const SizedBox(width: AppDimensions.spaceSm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PERMANENTLY DECOMMISSIONED',
                              style: AppTypography.headlineSm.copyWith(fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'This bearing has completed its operational lifecycle. Re-installation is strictly prohibited.',
                              style: AppTypography.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: AppDimensions.spaceSm),

              IndustrialButton.secondary(
                label: loc.translate('scan_bearing_qr'),
                icon: Icons.qr_code_scanner,
                onPressed: () => Navigator.pushReplacementNamed(context, AppRoutes.qrScanner),
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

  Widget _buildSpecRow(String label, String value, {bool isMono = false, bool isHighlightDanger = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: AppTypography.bodyMd.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppColors.primary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 5,
            child: Text(
              value,
              style: isHighlightDanger
                  ? AppTypography.labelMd.copyWith(
                      color: const Color(0xFFDC2626),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    )
                  : (isMono
                      ? AppTypography.mono.copyWith(fontWeight: FontWeight.w600, fontSize: 13.5)
                      : AppTypography.labelMd.copyWith(fontWeight: FontWeight.w600, fontSize: 14)),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
