import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../../qr_generation/data/repositories/qr_management_repository.dart';
import '../widgets/admin_view_header.dart';

class AdminOverviewView extends StatefulWidget {
  final VoidCallback onNavigateToGeneration;
  final VoidCallback? onNavigateToWarranty;
  final VoidCallback onNavigateToRegistry;
  final VoidCallback? onNavigateToSecurity;
  final VoidCallback? onNavigateToRoles;
  final VoidCallback? onNavigateToCustomers;

  const AdminOverviewView({
    super.key,
    required this.onNavigateToGeneration,
    this.onNavigateToWarranty,
    required this.onNavigateToRegistry,
    this.onNavigateToSecurity,
    this.onNavigateToRoles,
    this.onNavigateToCustomers,
  });

  @override
  State<AdminOverviewView> createState() => _AdminOverviewViewState();
}

class _AdminOverviewViewState extends State<AdminOverviewView> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic> _metrics = {};

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      Map<String, dynamic> remoteMetrics = {};
      if (SupabaseService.isInitialized) {
        try {
          remoteMetrics = await SupabaseService.fetchAdminDashboardMetrics();
        } catch (_) {}
      }

      await QrManagementRepository.loadFromLocalStorage();
      final localMetrics = QrManagementRepository.computeTelemetryMetrics();

      int safeInt(dynamic val) {
        if (val == null) return 0;
        if (val is int) return val;
        return int.tryParse(val.toString()) ?? 0;
      }

      // Merge remote Supabase aggregates with real-time in-memory session data
      final merged = {
        'total_qr_codes': max(safeInt(remoteMetrics['total_qr_codes']), safeInt(localMetrics['total_qr_codes'])),
        'unactivated_qr_codes': max(safeInt(remoteMetrics['unactivated_qr_codes']), safeInt(localMetrics['unactivated_qr_codes'])),
        'currently_in_bearings': max(safeInt(remoteMetrics['currently_in_bearings']), safeInt(localMetrics['currently_in_bearings'])),
        'currently_out_bearings': max(safeInt(remoteMetrics['currently_out_bearings']), safeInt(localMetrics['currently_out_bearings'])),
        'active_warranties': max(safeInt(remoteMetrics['active_warranties']), safeInt(localMetrics['active_warranties'])),
        'expired_warranties': max(safeInt(remoteMetrics['expired_warranties']), safeInt(localMetrics['expired_warranties'])),
        'total_scans': max(safeInt(remoteMetrics['total_scans']), safeInt(localMetrics['total_scans'])),
        'invalid_attempts': max(safeInt(remoteMetrics['invalid_attempts']), safeInt(localMetrics['invalid_attempts'])),
        'total_customers': max(safeInt(remoteMetrics['total_customers']), safeInt(localMetrics['total_customers'])),
        'total_batches': max(safeInt(remoteMetrics['total_batches']), safeInt(localMetrics['total_batches'])),
        'flagged_bearings': max(safeInt(remoteMetrics['flagged_bearings']), safeInt(localMetrics['flagged_bearings'])),
      };

      if (mounted) {
        setState(() {
          _metrics = merged;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _metrics = QrManagementRepository.computeTelemetryMetrics();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
            SizedBox(height: 16),
            Text('RETRIEVING PRODUCTION METRICS & AUDIT LOGS...', style: AppTypography.caption),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.primary),
              const SizedBox(height: 12),
              Text(_errorMessage!, style: AppTypography.bodySm, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              IndustrialButton(
                label: 'RETRY CONNECTION',
                width: 160,
                onPressed: _loadMetrics,
              ),
            ],
          ),
        ),
      );
    }

    final totalQr = _metrics['total_qr_codes'] ?? 0;
    final unactivated = _metrics['unactivated_qr_codes'] ?? 0;
    final currentlyIn = _metrics['currently_in_bearings'] ?? 0;
    final currentlyOut = _metrics['currently_out_bearings'] ?? 0;
    final activeWarranties = _metrics['active_warranties'] ?? 0;
    final expiredWarranties = _metrics['expired_warranties'] ?? 0;
    final totalCustomers = _metrics['total_customers'] ?? 0;
    final totalBatches = _metrics['total_batches'] ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 650;
        final contentPadding = isMobile
            ? const EdgeInsets.all(AppDimensions.gutterMobile)
            : const EdgeInsets.all(AppDimensions.gutterDesktop);

        return SingleChildScrollView(
          padding: contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Clean, responsive header (stacks on mobile, side-by-side on desktop)
              AdminViewHeader(
                title: 'Production Telemetry',
                actions: [
                  InkWell(
                    onTap: _loadMetrics,
                    borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primary, width: 1.5),
                        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sync, size: 16, color: AppColors.primary),
                          SizedBox(width: 6),
                          Text('SYNC NOW', style: AppTypography.caption),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // Responsive Metrics Grid (Desktop 4-col, Laptop 3-col, Tablet 2-col, Mobile 1-col)
              Builder(
                builder: (context) {
                  int crossAxisCount = 4;
                  double aspectRatio = 1.95;

                  if (constraints.maxWidth < 560) {
                    crossAxisCount = 1;
                    aspectRatio = 2.8;
                  } else if (constraints.maxWidth < 880) {
                    crossAxisCount = 2;
                    aspectRatio = 1.85;
                  } else if (constraints.maxWidth < 1250) {
                    crossAxisCount = 3;
                    aspectRatio = 1.85;
                  }

                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: AppDimensions.spaceMd,
                    mainAxisSpacing: AppDimensions.spaceMd,
                    childAspectRatio: aspectRatio,
                    children: [
                      _MetricCard(
                        title: 'TOTAL QR CODES',
                        value: '$totalQr',
                        icon: Icons.qr_code_2,
                      ),
                      _MetricCard(
                        title: 'NOT YET ACTIVATED',
                        value: '$unactivated',
                        icon: Icons.pending_actions,
                      ),
                      _MetricCard(
                        title: 'CURRENTLY IN',
                        value: '$currentlyIn',
                        icon: Icons.login,
                      ),
                      _MetricCard(
                        title: 'CURRENTLY OUT',
                        value: '$currentlyOut',
                        icon: Icons.logout,
                      ),
                      _MetricCard(
                        title: 'ACTIVE WARRANTIES',
                        value: '$activeWarranties',
                        icon: Icons.verified_user,
                      ),
                      _MetricCard(
                        title: 'EXPIRED WARRANTIES',
                        value: '$expiredWarranties',
                        icon: Icons.timer_off,
                      ),
                      _MetricCard(
                        title: 'TOTAL CUSTOMERS',
                        value: '$totalCustomers',
                        icon: Icons.corporate_fare,
                      ),
                      _MetricCard(
                        title: 'PRODUCTION BATCHES',
                        value: '$totalBatches',
                        icon: Icons.inventory_2,
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: AppDimensions.spaceLg),

              // Quick Action Launchers
              const Text('Administrative Modules', style: AppTypography.headlineSm),
              const SizedBox(height: AppDimensions.spaceSm),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ActionShortcutCard(
                    title: 'QR Generation',
                    subtitle: 'Generate bulk serial manifests',
                    icon: Icons.add_box,
                    onTap: widget.onNavigateToGeneration,
                  ),
                  _ActionShortcutCard(
                    title: 'QR Registry',
                    subtitle: 'Search, block & manifest export',
                    icon: Icons.table_chart,
                    onTap: widget.onNavigateToRegistry,
                  ),
                  _ActionShortcutCard(
                    title: 'Role Assignment',
                    subtitle: 'User clearance & permissions',
                    icon: Icons.admin_panel_settings,
                    onTap: widget.onNavigateToRoles ?? () {},
                  ),
                  _ActionShortcutCard(
                    title: 'Customer Accounts',
                    subtitle: 'Authorized enterprise facilities',
                    icon: Icons.corporate_fare,
                    onTap: widget.onNavigateToCustomers ?? () {},
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spaceXl),
            ],
          ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final String? badgeText;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    // ignore: unused_element_parameter
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    return IndustrialCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.caption.copyWith(
                    letterSpacing: 0.5,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 16, color: AppColors.primary),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: AppTypography.headlineMd),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionShortcutCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionShortcutCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 560;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
      child: Container(
        width: isMobile ? double.infinity : 250,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: AppColors.primary, width: 1.5),
          borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
              ),
              child: Icon(icon, color: AppColors.background, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.labelMd, overflow: TextOverflow.ellipsis),
                  Text(subtitle, style: AppTypography.caption.copyWith(fontSize: 10), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
