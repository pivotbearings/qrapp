import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../../../core/widgets/industrial_status_badge.dart';
import '../../../bearing_verification/data/models/bearing_model.dart';
import '../../../bearing_verification/data/repositories/bearing_repository.dart';

/// Modal dialog and full-screen inspector for complete bearing lifecycle history
class BearingLifecycleInspectorDialog extends StatefulWidget {
  final String bearingId;

  const BearingLifecycleInspectorDialog({
    super.key,
    required this.bearingId,
  });

  static Future<void> show(BuildContext context, String bearingId) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => BearingLifecycleInspectorDialog(bearingId: bearingId),
    );
  }

  @override
  State<BearingLifecycleInspectorDialog> createState() => _BearingLifecycleInspectorDialogState();
}

class _BearingLifecycleInspectorDialogState extends State<BearingLifecycleInspectorDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _lifecycleData;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await SupabaseService.fetchBearingFullLifecycleDetails(widget.bearingId);
      if (data != null) {
        setState(() {
          _lifecycleData = data;
          _isLoading = false;
        });
      } else {
        final localBearing = await BearingRepositoryImpl().getBearingById(widget.bearingId);
        if (localBearing != null) {
          setState(() {
            _lifecycleData = _generateRealLifecycle(localBearing);
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = 'Bearing ID ${widget.bearingId} was not found in the registry.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load bearing lifecycle: $e';
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic> _generateRealLifecycle(BearingModel bearing) {
    return {
      'bearing_id': bearing.id,
      'model_number': bearing.modelNumber,
      'batch_code': bearing.batchCode,
      'plant_location': bearing.plantLocation,
      'current_lifecycle_state': bearing.state == BearingLifecycleState.currentlyIn
          ? 'CURRENTLY_IN'
          : (bearing.state == BearingLifecycleState.currentlyOut ? 'CURRENTLY_OUT' : 'NOT_ACTIVATED'),
      'is_flagged': false,
      'flag_reason': null,
      'warranty_plan': {
        'title': '${bearing.warrantyDurationMonths} Months Warranty',
        'duration_months': bearing.warrantyDurationMonths,
      },
      'assigned_customer': bearing.customerName != null
          ? {
              'full_name': 'Authorized Client',
              'company_name': bearing.customerName,
              'facility_code': 'PBI-FAC',
            }
          : null,
      'first_in_timestamp': bearing.firstInDate?.toIso8601String(),
      'warranty_expiry_timestamp': bearing.warrantyExpiryDate?.toIso8601String(),
      'is_warranty_active': !bearing.isWarrantyExpired && bearing.firstInDate != null,
      'installation_cycles': [],
      'lifecycle_events': [],
    };
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    return Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        side: const BorderSide(color: AppColors.primary, width: 2.0),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 32,
        vertical: isMobile ? 16 : 32,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 960,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          children: [
            // Modal Top Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.primary, width: 1.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history_toggle_off, color: AppColors.primary, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LIFECYCLE TELEMETRY: ${widget.bearingId}', style: AppTypography.headlineSm),
                        const Text('AUTHORITATIVE REGISTRY & POSTGRESQL AUDIT TRAIL', style: AppTypography.caption),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.primary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Modal Body
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
                          SizedBox(height: 12),
                          Text('RETRIEVING BEARING TELEMETRY...', style: AppTypography.caption),
                        ],
                      ),
                    )
                  : _errorMessage != null
                      ? Center(
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
                                  label: 'RETRY QUERY',
                                  width: 140,
                                  onPressed: _fetchDetails,
                                ),
                              ],
                            ),
                          ),
                        )
                      : _buildLifecycleContent(context, isMobile),
            ),

            // Modal Footer Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.primary, width: 1.0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('BEARING SERIAL ID: ${widget.bearingId}', style: AppTypography.caption),
                  IndustrialButton(
                    label: 'CLOSE INSPECTOR',
                    width: 140,
                    variant: IndustrialButtonVariant.secondary,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLifecycleContent(BuildContext context, bool isMobile) {
    final data = _lifecycleData!;
    final state = data['current_lifecycle_state']?.toString() ?? 'NOT_ACTIVATED';
    final isFlagged = data['is_flagged'] == true;
    final plan = data['warranty_plan'] as Map<String, dynamic>? ?? {};
    final customer = data['assigned_customer'] as Map<String, dynamic>? ?? {};
    final cycles = (data['installation_cycles'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final events = (data['lifecycle_events'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final firstInStr = data['first_in_timestamp']?.toString();
    final expiryStr = data['warranty_expiry_timestamp']?.toString();
    final isWarrantyActive = data['is_warranty_active'] == true;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Overview Bar
          IndustrialCard(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('MODEL SPECIFICATION', style: AppTypography.caption),
                    Text(data['model_number']?.toString() ?? 'PBI-STANDARD', style: AppTypography.headlineSm),
                    Text('BATCH: ${data['batch_code']} | PLANT: ${data['plant_location']}', style: AppTypography.caption),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IndustrialStatusBadge(statusText: state),
                    if (isFlagged) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                        ),
                        child: const Text('BLOCKED', style: TextStyle(color: AppColors.background, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Warranty Anchor and Customer Info (Side by side on desktop, stacked on mobile)
          if (!isMobile)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildWarrantyAnchorCard(plan, firstInStr, expiryStr, isWarrantyActive)),
                const SizedBox(width: 16),
                Expanded(child: _buildCustomerCard(customer)),
              ],
            )
          else ...[
            _buildWarrantyAnchorCard(plan, firstInStr, expiryStr, isWarrantyActive),
            const SizedBox(height: 12),
            _buildCustomerCard(customer),
          ],

          const SizedBox(height: 24),

          // 3. Every Installation Cycle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('OPERATIONAL INSTALLATION CYCLES', style: AppTypography.headlineSm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                ),
                child: Text('TOTAL CYCLES: ${cycles.length}', style: AppTypography.caption),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (cycles.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 1.0),
                borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              ),
              child: const Center(
                child: Text('NO INSTALLATION CYCLES RECORDED YET (BEARING NOT YET INSTALLED)', style: AppTypography.caption),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cycles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final cycle = cycles[index];
                return _buildCycleRow(cycle);
              },
            ),

          const SizedBox(height: 24),

          // 4. Authoritative Lifecycle Audit Events
          const Text('LIFECYCLE AUDIT TRAIL', style: AppTypography.headlineSm),
          const SizedBox(height: 8),
          if (events.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 1.0),
                borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              ),
              child: const Center(child: Text('NO SYSTEM EVENTS LOGGED', style: AppTypography.caption)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: events.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final evt = events[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary, width: 1.0),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                        ),
                        child: Text(evt['event_type']?.toString() ?? 'LOG', style: const TextStyle(color: AppColors.background, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(evt['notes']?.toString() ?? 'Status Transition', style: AppTypography.labelMd),
                            Text('TIMESTAMP: ${evt['server_timestamp'] ?? 'N/A'} | OPERATOR: ${evt['operator_id'] ?? 'SYSTEM'}', style: AppTypography.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildWarrantyAnchorCard(
    Map<String, dynamic> plan,
    String? firstInStr,
    String? expiryStr,
    bool isWarrantyActive,
  ) {
    return IndustrialCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ORIGINAL WARRANTY ANCHOR', style: AppTypography.caption),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isWarrantyActive ? AppColors.primary : Colors.transparent,
                  border: Border.all(color: AppColors.primary),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                ),
                child: Text(
                  firstInStr == null
                      ? 'NOT ACTIVATED'
                      : (isWarrantyActive ? 'WARRANTY ACTIVE' : 'WARRANTY EXPIRED'),
                  style: TextStyle(
                    color: isWarrantyActive ? AppColors.background : AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(plan['title']?.toString() ?? 'Standard Industrial', style: AppTypography.headlineSm),
          Text('DURATION: ${plan['duration_months'] ?? 6} CALENDAR MONTHS', style: AppTypography.caption),
          const Divider(height: 20),
          _buildInfoRow('First IN (Activation):', firstInStr ?? 'Pending initial installation'),
          const SizedBox(height: 6),
          _buildInfoRow('Authoritative Expiry:', expiryStr ?? 'Pending initial installation'),
        ],
      ),
    );
  }

  Widget _buildCustomerCard(Map<String, dynamic> customer) {
    return IndustrialCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ASSIGNED CUSTOMER & FACILITY', style: AppTypography.caption),
          const SizedBox(height: 10),
          Text(customer['company_name']?.toString() ?? 'Unassigned Account', style: AppTypography.headlineSm),
          Text('CONTACT: ${customer['full_name'] ?? 'General Operator'}', style: AppTypography.labelMd),
          const Divider(height: 20),
          _buildInfoRow('Facility Code:', customer['facility_code']?.toString() ?? 'PBI-CENTRAL-01'),
          const SizedBox(height: 6),
          _buildInfoRow('Security Level:', 'RESTRICTED / AUTHORIZED ADMINISTRATOR'),
        ],
      ),
    );
  }

  Widget _buildCycleRow(Map<String, dynamic> cycle) {
    final cycleNum = cycle['cycle_number'] ?? 1;
    final inTs = cycle['in_timestamp']?.toString() ?? 'N/A';
    final outTs = cycle['out_timestamp']?.toString();
    final duration = cycle['operating_duration_interval']?.toString() ?? (outTs == null ? 'In Operation' : 'N/A');
    final wasActiveAtOut = cycle['was_warranty_active_at_out'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.primary, width: 1.5),
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                    ),
                    child: Text('CYCLE #$cycleNum', style: const TextStyle(color: AppColors.background, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                  const SizedBox(width: 10),
                  Text(outTs == null ? 'CURRENT ACTIVE INSTALLATION' : 'COMPLETED INSTALLATION CYCLE', style: AppTypography.labelMd),
                ],
              ),
              if (wasActiveAtOut != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                  ),
                  child: Text(
                    wasActiveAtOut ? 'WARRANTY ACTIVE AT OUT' : 'WARRANTY EXPIRED AT OUT',
                    style: AppTypography.caption,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _buildMiniCycleStat('IN TIMESTAMP', inTs),
              _buildMiniCycleStat('OUT TIMESTAMP', outTs ?? 'STILL CURRENTLY IN'),
              _buildMiniCycleStat('USAGE DURATION', duration),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCycleStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption),
        const SizedBox(height: 2),
        Text(value, style: AppTypography.labelMd),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.caption),
        Text(value, style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
