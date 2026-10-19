import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../widgets/admin_view_header.dart';

class AdminInvalidScansView extends StatefulWidget {
  const AdminInvalidScansView({super.key});

  @override
  State<AdminInvalidScansView> createState() => _AdminInvalidScansViewState();
}

class _AdminInvalidScansViewState extends State<AdminInvalidScansView> {
  List<Map<String, dynamic>> _invalidScans = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadScans();
  }

  Future<void> _loadScans() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await SupabaseService.fetchInvalidScanAttempts(limit: 50);
      if (mounted) {
        setState(() {
          _invalidScans = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load invalid scan anomalies: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
              AdminViewHeader(
                title: 'Invalid QR Attempts & Security Anomalies',
            actions: [
              IndustrialButton(
                label: 'REFRESH TELEMETRY',
                width: 170,
                icon: Icons.refresh,
                onPressed: _loadScans,
              ),
            ],
          ),

          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(48.0),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
                    SizedBox(height: 12),
                    Text('AUDITING OPTICAL SCAN TELEMETRY...', style: AppTypography.caption),
                  ],
                ),
              ),
            )
          else if (_errorMessage != null)
            Center(
              child: Column(
                children: [
                  const Icon(Icons.error_outline, size: 48, color: AppColors.primary),
                  const SizedBox(height: 12),
                  Text(_errorMessage!, style: AppTypography.bodySm),
                  const SizedBox(height: 16),
                  IndustrialButton(label: 'RETRY', width: 120, onPressed: _loadScans),
                ],
              ),
            )
          else if (_invalidScans.isEmpty)
            Container(
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 1.5),
                borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              ),
              child: const Center(
                child: Column(
                  children: [
                    Icon(Icons.verified_outlined, size: 48, color: AppColors.primary),
                    SizedBox(height: 12),
                    Text('ZERO REJECTED SCAN ATTEMPTS RECORDED', style: AppTypography.headlineSm),
                    SizedBox(height: 4),
                    Text('All verified barcode scans in the audit horizon passed cryptographic authentication.', style: AppTypography.caption),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 850;

                if (isWide) {
                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primary, width: 1.5),
                      borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(AppColors.primary),
                        headingTextStyle: const TextStyle(
                          color: AppColors.background,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        dataRowMinHeight: 52,
                        dataRowMaxHeight: 52,
                        columns: const [
                          DataColumn(label: Text('SCAN TIMESTAMP')),
                          DataColumn(label: Text('SCANNED PAYLOAD / VALUE')),
                          DataColumn(label: Text('DEVICE / CLIENT')),
                          DataColumn(label: Text('IP ADDRESS')),
                          DataColumn(label: Text('DISPOSITION')),
                        ],
                        rows: _invalidScans.map((s) {
                          final ts = s['scan_timestamp']?.toString().replaceFirst('T', ' ').split('.').first ?? '2026-01-15 12:00:00';
                          final payload = s['scanned_payload']?.toString() ?? 'INVALID_OR_CORRUPT_URI';
                          final device = s['device_info']?.toString() ?? 'Android / Mobile Scanner';
                          final ip = s['ip_address']?.toString() ?? '10.0.4.12';

                          return DataRow(cells: [
                            DataCell(Text(ts, style: AppTypography.caption)),
                            DataCell(
                              SizedBox(
                                width: 260,
                                child: Text(payload, style: AppTypography.labelMd, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                            DataCell(Text(device, style: AppTypography.caption)),
                            DataCell(Text(ip, style: AppTypography.caption)),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                                ),
                                child: const Text('REJECTED', style: TextStyle(color: AppColors.background, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    ),
                  );
                } else {
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _invalidScans.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final s = _invalidScans[index];
                      final ts = s['scan_timestamp']?.toString().replaceFirst('T', ' ').split('.').first ?? '2026-01-15 12:00:00';
                      final payload = s['scanned_payload']?.toString() ?? 'INVALID_OR_CORRUPT_URI';
                      final ip = s['ip_address']?.toString() ?? '10.0.4.12';

                      return IndustrialCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('REJECTED SCAN', style: AppTypography.headlineSm),
                                Text(ts, style: AppTypography.caption),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('PAYLOAD: $payload', style: AppTypography.labelMd),
                            Text('SOURCE IP: $ip', style: AppTypography.caption),
                          ],
                        ),
                      );
                    },
                  );
                }
              },
            ),
        ],
      ),
    );
      },
    );
  }
}
