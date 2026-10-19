import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../../admin_dashboard/presentation/widgets/admin_view_header.dart';
import '../../../qr_generation/data/repositories/qr_management_repository.dart';

class WarrantyAssignmentScreen extends StatefulWidget {
  final bool isEmbedded;
  const WarrantyAssignmentScreen({super.key, this.isEmbedded = false});

  @override
  State<WarrantyAssignmentScreen> createState() => _WarrantyAssignmentScreenState();
}

class _WarrantyAssignmentScreenState extends State<WarrantyAssignmentScreen> {
  final QrManagementRepository _repo = QrManagementRepository();

  List<Map<String, dynamic>> _warrantyPlans = [];
  List<Map<String, dynamic>> _bearings = [];
  final Map<String, String> _stagedAssignments = {}; // bearingId -> warrantyPlanId
  final Set<String> _selectedIds = {};

  String? _currentSelectedPlanId;
  bool _isLoading = true;
  bool _isCommitting = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      final plans = await _repo.fetchWarrantyPlans();
      final qrs = await _repo.fetchQrCodes(limit: 50);

      setState(() {
        _warrantyPlans = plans;
        if (plans.isNotEmpty) {
          _currentSelectedPlanId = plans.first['id'].toString();
        }
        _bearings = qrs;
        _stagedAssignments.clear();
        _selectedIds.clear();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Failed to load registry: $e';
      });
    }
  }

  void _stageSelectedToCurrentPlan() {
    if (_selectedIds.isEmpty || _currentSelectedPlanId == null) return;

    setState(() {
      for (final id in _selectedIds) {
        _stagedAssignments[id] = _currentSelectedPlanId!;
      }
      _selectedIds.clear();
    });
  }

  void _stageSingle(String bearingId, String planId) {
    setState(() {
      _stagedAssignments[bearingId] = planId;
    });
  }

  Future<void> _commitAssignments() async {
    if (_stagedAssignments.isEmpty) return;

    setState(() {
      _isCommitting = true;
      _statusMessage = null;
    });

    try {
      final payload = _stagedAssignments.entries.map((entry) {
        return {
          'bearing_id': entry.key,
          'warranty_plan_id': entry.value,
        };
      }).toList();

      final res = await _repo.assignWarrantiesBulk(payload);
      final count = res['updated_count'] ?? payload.length;

      setState(() {
        _isCommitting = false;
        _stagedAssignments.clear();
        _statusMessage = 'Successfully committed $count warranty assignments.';
      });

      _loadData();
    } catch (e) {
      setState(() {
        _isCommitting = false;
        _statusMessage = 'Commit failed: $e';
      });
    }
  }

  String _getPlanTitle(String planId) {
    final match = _warrantyPlans.firstWhere(
      (p) => p['id'].toString() == planId,
      orElse: () => {'title': '6 Months Heavy Duty', 'duration_months': 6},
    );
    return '${match['title']} (${match['duration_months']}M)';
  }

  @override
  Widget build(BuildContext context) {
    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimensions.gutterDesktop),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminViewHeader(
                title: 'Warranty Assignment Engine',
                subtitle: 'ASSIGN STANDARD OR CUSTOM COVERAGE INDIVIDUALLY OR IN BULK',
                actions: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primary, width: 1.0),
                      borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                    ),
                    child: const Text('SYS_NODE: ALLOCATION', style: AppTypography.caption),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Assign standard or custom warranty coverage individually or in bulk. Expiry anchors strictly upon the first IN event.',
                style: AppTypography.bodyMd,
              ),
              const SizedBox(height: AppDimensions.spaceLg),

              if (_statusMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    border: Border.all(color: AppColors.primary, width: 2.0),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                  ),
                  child: Text(_statusMessage!, style: AppTypography.labelMd),
                ),
                const SizedBox(height: AppDimensions.spaceMd),
              ],

              // Bulk Staging Action Bar Card
              IndustrialCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            '${_selectedIds.length} Bearings Selected | ${_stagedAssignments.length} Staged for Commit',
                            style: AppTypography.labelMd,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_stagedAssignments.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() => _stagedAssignments.clear()),
                            child: const Text('CLEAR STAGED', style: TextStyle(color: AppColors.primary)),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.spaceSm),
                    LayoutBuilder(
                      builder: (context, cardConstraints) {
                        final isCompact = cardConstraints.maxWidth < 700;
                        if (isCompact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DropdownButtonFormField<String>(
                                initialValue: _currentSelectedPlanId,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'Warranty Plan for Selection',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppDimensions.radiusMicro)),
                                ),
                                items: _warrantyPlans.map((plan) {
                                  return DropdownMenuItem<String>(
                                    value: plan['id'].toString(),
                                    child: Text('${plan['title']} (${plan['duration_months']}M)', overflow: TextOverflow.ellipsis),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _currentSelectedPlanId = val);
                                },
                              ),
                              const SizedBox(height: AppDimensions.spaceSm),
                              IndustrialButton(
                                label: 'STAGE SELECTION',
                                icon: Icons.playlist_add,
                                variant: IndustrialButtonVariant.secondary,
                                onPressed: _selectedIds.isEmpty ? null : _stageSelectedToCurrentPlan,
                              ),
                              const SizedBox(height: AppDimensions.spaceSm),
                              IndustrialButton(
                                label: _isCommitting ? 'SAVING...' : 'COMMIT ASSIGNMENTS (${_stagedAssignments.length})',
                                icon: Icons.check,
                                variant: IndustrialButtonVariant.primary,
                                isLoading: _isCommitting,
                                onPressed: _stagedAssignments.isEmpty || _isCommitting ? null : _commitAssignments,
                              ),
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: DropdownButtonFormField<String>(
                                initialValue: _currentSelectedPlanId,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'Warranty Plan for Selection',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppDimensions.radiusMicro)),
                                ),
                                items: _warrantyPlans.map((plan) {
                                  return DropdownMenuItem<String>(
                                    value: plan['id'].toString(),
                                    child: Text('${plan['title']} (${plan['duration_months']}M)', overflow: TextOverflow.ellipsis),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _currentSelectedPlanId = val);
                                },
                              ),
                            ),
                            const SizedBox(width: AppDimensions.spaceMd),
                            IndustrialButton(
                              label: 'STAGE SELECTION',
                              icon: Icons.playlist_add,
                              variant: IndustrialButtonVariant.secondary,
                              width: 170,
                              onPressed: _selectedIds.isEmpty ? null : _stageSelectedToCurrentPlan,
                            ),
                            const SizedBox(width: AppDimensions.spaceSm),
                            IndustrialButton(
                              label: _isCommitting ? 'SAVING...' : 'COMMIT ASSIGNMENTS (${_stagedAssignments.length})',
                              icon: Icons.check,
                              variant: IndustrialButtonVariant.primary,
                              width: 250,
                              isLoading: _isCommitting,
                              onPressed: _stagedAssignments.isEmpty || _isCommitting ? null : _commitAssignments,
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppDimensions.spaceLg),

              // Bearing Allocation Grid
              if (_isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppColors.primary)))
              else
                IndustrialCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('BEARING ALLOCATION REGISTRY', style: AppTypography.labelMd),
                      const SizedBox(height: AppDimensions.spaceSm),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: [
                            DataColumn(
                              label: Checkbox(
                                value: _selectedIds.length == _bearings.length && _bearings.isNotEmpty,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedIds.addAll(_bearings.map((b) => b['bearing_id'].toString()));
                                    } else {
                                      _selectedIds.clear();
                                    }
                                  });
                                },
                                activeColor: AppColors.primary,
                              ),
                            ),
                            const DataColumn(label: Text('BEARING ID', style: AppTypography.labelMd)),
                            const DataColumn(label: Text('CURRENT WARRANTY', style: AppTypography.labelMd)),
                            const DataColumn(label: Text('STAGED PLAN', style: AppTypography.labelMd)),
                            const DataColumn(label: Text('INDIVIDUAL ASSIGN', style: AppTypography.labelMd)),
                          ],
                          rows: _bearings.map((b) {
                            final id = b['bearing_id'].toString();
                            final isSelected = _selectedIds.contains(id);
                            final stagedPlanId = _stagedAssignments[id];

                            return DataRow(
                              selected: isSelected,
                              onSelectChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedIds.add(id);
                                  } else {
                                    _selectedIds.remove(id);
                                  }
                                });
                              },
                              cells: [
                                DataCell(
                                  Checkbox(
                                    value: isSelected,
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          _selectedIds.add(id);
                                        } else {
                                          _selectedIds.remove(id);
                                        }
                                      });
                                    },
                                    activeColor: AppColors.primary,
                                  ),
                                ),
                                DataCell(Text(id, style: AppTypography.labelMd)),
                                DataCell(Text('${b['duration_months']} Months', style: AppTypography.bodySm)),
                                DataCell(
                                  Text(
                                    stagedPlanId != null ? _getPlanTitle(stagedPlanId) : '—',
                                    style: AppTypography.bodySm.copyWith(
                                      fontWeight: stagedPlanId != null ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  DropdownButton<String>(
                                    hint: const Text('Quick Assign', style: AppTypography.caption),
                                    value: stagedPlanId,
                                    underline: const SizedBox(),
                                    items: _warrantyPlans.map((plan) {
                                      return DropdownMenuItem<String>(
                                        value: plan['id'].toString(),
                                        child: Text('${plan['duration_months']}M Tier', style: AppTypography.caption),
                                      );
                                    }).toList(),
                                    onChanged: (newPlan) {
                                      if (newPlan != null) _stageSingle(id, newPlan);
                                    },
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const IndustrialAppBar(title: 'Warranty Assignment'),
      body: SafeArea(child: content),
    );
  }
}
