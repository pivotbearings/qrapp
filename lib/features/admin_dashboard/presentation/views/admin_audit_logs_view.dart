import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../widgets/admin_view_header.dart';

class AdminAuditLogsView extends StatefulWidget {
  const AdminAuditLogsView({super.key});

  @override
  State<AdminAuditLogsView> createState() => _AdminAuditLogsViewState();
}

class _AdminAuditLogsViewState extends State<AdminAuditLogsView> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await SupabaseService.fetchAdminAuditLogs(limit: 50);
      if (mounted) {
        setState(() {
          _logs = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load audit trail: $e';
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
                title: 'Admin Audit History',
                actions: [
                  IndustrialButton(
                    label: 'REFRESH AUDIT',
                    width: 150,
                    icon: Icons.refresh,
                    onPressed: _loadLogs,
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
                    Text('AUDITING ADMINISTRATIVE TRAIL...', style: AppTypography.caption),
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
                  IndustrialButton(label: 'RETRY', width: 120, onPressed: _loadLogs),
                ],
              ),
            )
          else if (_logs.isEmpty)
            Container(
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 1.5),
                borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              ),
              child: const Center(
                child: Column(
                  children: [
                    Icon(Icons.history_edu, size: 48, color: AppColors.primary),
                    SizedBox(height: 12),
                    Text('NO RECENT ADMINISTRATIVE OPERATIONS LOGGED', style: AppTypography.headlineSm),
                    SizedBox(height: 4),
                    Text('Operations such as batch creations, warranty modifications, and bearing blocks are recorded here.', style: AppTypography.caption),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;

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
                          DataColumn(label: Text('TIMESTAMP')),
                          DataColumn(label: Text('OPERATOR')),
                          DataColumn(label: Text('OPERATION')),
                          DataColumn(label: Text('TARGET ENTITY')),
                          DataColumn(label: Text('IP ADDRESS')),
                          DataColumn(label: Text('SECURITY STATUS')),
                        ],
                        rows: _logs.map((log) {
                          final ts = log['created_at']?.toString().replaceFirst('T', ' ').split('.').first ?? '—';
                          final profile = log['profiles'] as Map<String, dynamic>?;
                          final adminName = profile?['full_name']?.toString() ?? 'System';
                          final action = log['action']?.toString() ?? 'OPERATION';
                          final entity = log['target_entity']?.toString() ?? 'TARGET';
                          final ip = log['ip_address']?.toString() ?? '—';

                          return DataRow(cells: [
                            DataCell(Text(ts, style: AppTypography.caption)),
                            DataCell(Text(adminName, style: AppTypography.labelMd)),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                                ),
                                child: Text(action, style: const TextStyle(color: AppColors.background, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            DataCell(Text(entity, style: AppTypography.caption)),
                            DataCell(Text(ip, style: AppTypography.caption)),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.primary),
                                  borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                                ),
                                child: const Text('VERIFIED', style: AppTypography.caption),
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
                    itemCount: _logs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      final ts = log['created_at']?.toString().replaceFirst('T', ' ').split('.').first ?? '—';
                      final profile = log['profiles'] as Map<String, dynamic>?;
                      final adminName = profile?['full_name']?.toString() ?? 'System';
                      final action = log['action']?.toString() ?? 'OPERATION';
                      final entity = log['target_entity']?.toString() ?? 'TARGET';

                      return IndustrialCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(action, style: AppTypography.headlineSm),
                                Text(ts, style: AppTypography.caption),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('TARGET: $entity | OPERATOR: $adminName', style: AppTypography.labelMd),
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
