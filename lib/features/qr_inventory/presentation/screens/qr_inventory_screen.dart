import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/qr_export_service.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../../../core/widgets/industrial_status_badge.dart';
import '../../../../core/widgets/industrial_text_field.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../qr_generation/data/repositories/qr_management_repository.dart';
import '../../../admin_dashboard/presentation/widgets/bearing_lifecycle_inspector_dialog.dart';
import '../../../admin_dashboard/presentation/widgets/admin_view_header.dart';
import '../../../../core/widgets/app_snack_bar.dart';

class QrInventoryScreen extends StatefulWidget {
  final bool isEmbedded;
  const QrInventoryScreen({super.key, this.isEmbedded = false});

  @override
  State<QrInventoryScreen> createState() => _QrInventoryScreenState();
}

class _QrInventoryScreenState extends State<QrInventoryScreen> {
  final QrManagementRepository _repo = QrManagementRepository();
  final TextEditingController _searchCtrl = TextEditingController();

  int _activeFilterTab = 0;
  final List<String> _tabs = [
    'All Bearings',
    'Not Activated',
    'Currently IN',
    'Currently OUT',
  ];

  final List<String> _statusFilters = [
    'ALL',
    'NOT_ACTIVATED',
    'CURRENTLY_IN',
    'CURRENTLY_OUT',
  ];

  List<Map<String, dynamic>> _qrList = [];
  List<Map<String, dynamic>> _warrantyPlans = [];
  List<Map<String, dynamic>> _tenantsList = [];
  String _selectedTenantFilter = 'ALL';
  final Set<String> _selectedBearingIds = {};
  bool _isLoading = true;
  String? _errorMessage;

  // Pagination with strict page size of 10
  static const int _pageSize = 10;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.isEmbedded && !AuthController.instance.isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.customerHome);
        }
      });
      return;
    }
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await QrManagementRepository.loadFromLocalStorage();
      final auth = AuthController.instance;
      final isCustomer = !auth.isAdmin;
      final effectiveTenant = isCustomer
          ? (auth.userId ?? auth.userEmail)
          : (_selectedTenantFilter != 'ALL' ? _selectedTenantFilter : null);

      List<Map<String, dynamic>> tenants = [];
      if (auth.isAdmin) {
        try {
          tenants = await SupabaseService.fetchCustomerProfiles();
        } catch (_) {}
      }

      final plans = await _repo.fetchWarrantyPlans();
      List<Map<String, dynamic>> qrs;
      try {
        qrs = await _repo.fetchQrCodes(
          status: _statusFilters[_activeFilterTab],
          searchQuery: _searchCtrl.text.trim(),
          customerId: effectiveTenant,
        );
      } catch (_) {
        // Fallback: If querying for a specific tenant, strictly return empty to never leak other data
        if (effectiveTenant != null && effectiveTenant.isNotEmpty && effectiveTenant != 'ALL') {
          qrs = [];
        } else {
          qrs = await _repo.fetchQrCodes(
            status: _statusFilters[_activeFilterTab],
            searchQuery: _searchCtrl.text.trim(),
          );
        }
      }

      setState(() {
        _warrantyPlans = plans;
        _tenantsList = tenants;
        _qrList = qrs;
        _selectedBearingIds.clear();
        _currentPage = 0;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load registry: $e';
      });
    }
  }

  void _onSearchChanged(String val) {
    setState(() => _currentPage = 0);
    _loadData();
  }

  void _onTabSelected(int index) {
    setState(() {
      _activeFilterTab = index;
      _currentPage = 0;
    });
    _loadData();
  }

  void _toggleSelectAll(List<Map<String, dynamic>> currentPagedList) {
    setState(() {
      final pagedIds = currentPagedList.map((e) => e['bearing_id'].toString()).toSet();
      final allSelected = pagedIds.every(_selectedBearingIds.contains);

      if (allSelected) {
        _selectedBearingIds.removeAll(pagedIds);
      } else {
        _selectedBearingIds.addAll(pagedIds);
      }
    });
  }

  void _toggleSelectOne(String id) {
    setState(() {
      if (_selectedBearingIds.contains(id)) {
        _selectedBearingIds.remove(id);
      } else {
        _selectedBearingIds.add(id);
      }
    });
  }

  // --- Actions: Inspect QR Matrix, Lifecycle, Bulk Warranty, Export ---

  void _showInspectModal(Map<String, dynamic> item) {
    final bearingId = item['bearing_id']?.toString() ?? 'PB-UNKNOWN';
    final modelNumber = item['model_number']?.toString() ?? 'PBI-6204-ZZ';
    final warrantyMonths = item['duration_months']?.toString() ?? '6';
    final lifecycleState = item['current_lifecycle_state']?.toString() ?? 'NOT_ACTIVATED';

    // Pure bearing code & characters payload for QR matrix (no URL, no domain)
    final payload = bearingId;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
          side: const BorderSide(color: AppColors.primary, width: 2.0),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
              ),
              child: const Icon(Icons.qr_code_scanner, color: AppColors.background, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'INSPECT QR MATRIX',
                style: AppTypography.headlineSm.copyWith(color: AppColors.primary),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // High-contrast industrial QR matrix container
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.primary, width: 2.0),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      QrImageView(
                        data: payload,
                        version: QrVersions.auto,
                        size: 200.0,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: AppColors.primary,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: AppColors.primary,
                        ),
                        errorStateBuilder: (cxt, err) {
                          return Container(
                            width: 200,
                            height: 200,
                            alignment: Alignment.center,
                            child: Text(
                              'Matrix render error: $err',
                              style: AppTypography.caption.copyWith(color: Colors.red),
                              textAlign: TextAlign.center,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        bearingId,
                        style: AppTypography.headlineSm.copyWith(
                          color: AppColors.primary,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceMd),

                // Specs breakdown card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary, width: 1.2),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                    color: AppColors.background,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInspectDetailRow('BEARING ID', bearingId),
                      _buildInspectDetailRow('MODEL NUMBER', modelNumber),
                      _buildInspectDetailRow('WARRANTY COVERAGE', '$warrantyMonths MONTHS'),
                      _buildInspectDetailRow('LIFECYCLE STATE', lifecycleState),
                      const Divider(color: AppColors.primary, height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('PAYLOAD VALUE', style: AppTypography.caption),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: payload));
                              AppSnackBar.showSuccess(context, 'QR Payload copied to clipboard');
                            },
                            child: const Row(
                              children: [
                                Icon(Icons.copy, size: 12, color: AppColors.primary),
                                SizedBox(width: 4),
                                Text(
                                  'COPY',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                        ),
                        child: SelectableText(
                          payload,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IndustrialButton(
            label: 'FULL LIFECYCLE',
            variant: IndustrialButtonVariant.secondary,
            width: 150,
            onPressed: () {
              Navigator.pop(ctx);
              BearingLifecycleInspectorDialog.show(context, bearingId);
            },
          ),
          IndustrialButton(
            label: 'CLOSE',
            width: 90,
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  Widget _buildInspectDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.caption),
          Text(
            value,
            style: AppTypography.labelMd.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _showBulkAssignDialog() {
    if (_selectedBearingIds.isEmpty || _warrantyPlans.isEmpty) return;

    String selectedPlanId = _warrantyPlans.first['id'].toString();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: AppColors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
            side: const BorderSide(color: AppColors.primary, width: 2.0),
          ),
          title: Text(
            'ASSIGN WARRANTY (${_selectedBearingIds.length} SELECTED)',
            style: AppTypography.headlineSm,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Assigning a new warranty plan to selected bearings will update their registered coverage. Generation and assignment do not start warranty coverage.',
                style: AppTypography.bodySm,
              ),
              const SizedBox(height: AppDimensions.spaceMd),
              DropdownButtonFormField<String>(
                initialValue: selectedPlanId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Select Warranty Horizon',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                  ),
                ),
                items: _warrantyPlans.map((plan) {
                  return DropdownMenuItem<String>(
                    value: plan['id'].toString(),
                    child: Text('${plan['title']} (${plan['duration_months']}M)'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setModalState(() => selectedPlanId = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL', style: TextStyle(color: AppColors.primary)),
            ),
            IndustrialButton(
              label: 'APPLY ASSIGNMENT',
              variant: IndustrialButtonVariant.primary,
              width: 170,
              onPressed: () async {
                Navigator.pop(ctx);
                final assignments = _selectedBearingIds.map((id) => {
                  'bearing_id': id,
                  'warranty_plan_id': selectedPlanId,
                }).toList();

                await _repo.assignWarrantiesBulk(assignments);
                _loadData();
              },
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getTargetItemsForExport() {
    if (_selectedBearingIds.isNotEmpty) {
      return _qrList.where((item) => _selectedBearingIds.contains(item['bearing_id'])).toList();
    }
    return _qrList;
  }

  void _exportTxt() {
    final items = _getTargetItemsForExport();
    if (items.isEmpty) return;
    QrExportService.downloadTxt(batchCode: 'REGISTRY_EXPORT', items: items);
  }

  void _exportCsv() {
    final items = _getTargetItemsForExport();
    if (items.isEmpty) return;
    QrExportService.downloadCsv(batchCode: 'REGISTRY_EXPORT', items: items);
  }

  void _exportWord() {
    final items = _getTargetItemsForExport();
    if (items.isEmpty) return;
    QrExportService.downloadWordDoc(batchCode: 'REGISTRY_EXPORT', items: items);
  }

  @override
  Widget build(BuildContext context) {
    // Pagination calculation
    final totalItems = _qrList.length;
    final totalPages = (totalItems == 0) ? 1 : ((totalItems + _pageSize - 1) ~/ _pageSize);
    if (_currentPage >= totalPages && totalPages > 0) {
      _currentPage = totalPages - 1;
    }
    final startIndex = _currentPage * _pageSize;
    final endIndex = (startIndex + _pageSize > totalItems) ? totalItems : startIndex + _pageSize;
    final pagedList = (totalItems == 0) ? <Map<String, dynamic>>[] : _qrList.sublist(startIndex, endIndex);

    final content = LayoutBuilder(
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
                title: 'QR Registry',
            actions: [
              IndustrialButton(
                label: 'WARRANTY CHECK',
                icon: Icons.verified_user,
                variant: IndustrialButtonVariant.secondary,
                width: 180,
                onPressed: () => Navigator.pushNamed(context, AppRoutes.warrantyCheck),
              ),
              const SizedBox(width: 8),
              if (AuthController.instance.isAdmin)
                IndustrialButton(
                  label: 'GENERATE QR CODES',
                  icon: Icons.add,
                  variant: IndustrialButtonVariant.primary,
                  width: 220,
                  onPressed: () => Navigator.pushNamed(context, AppRoutes.qrBulkGeneration),
                ),
            ],
          ),

          // Tenant Isolation Status Banner (Non-Admin Operators)
          if (!AuthController.instance.isAdmin) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border.all(color: AppColors.primary, width: 1.2),
                borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'TENANT ISOLATED MANIFEST • ${AuthController.instance.userName ?? 'Operator'} (${AuthController.instance.userEmail ?? ''})',
                      style: AppTypography.labelMd.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                    ),
                    child: const Text('ISOLATED VIEW', style: TextStyle(color: AppColors.background, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.spaceMd),
          ],

          // Admin Tenant Isolation Dropdown Selector
          if (AuthController.instance.isAdmin) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border.all(color: AppColors.primary, width: 1.2),
                borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              ),
              child: Row(
                children: [
                  const Icon(Icons.business, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'TENANT ISOLATION:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedTenantFilter,
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary),
                        items: [
                          const DropdownMenuItem(
                            value: 'ALL',
                            child: Text('All Tenants / Global Manifest (Enterprise Master)', style: AppTypography.bodySm),
                          ),
                          ..._tenantsList.map((t) {
                            final email = t['email']?.toString() ?? '';
                            final comp = (t['company_name'] ?? '').toString();
                            final fac = (t['facility_code'] ?? '').toString();
                            final label = comp.isNotEmpty ? '$comp ($fac • $email)' : email;
                            return DropdownMenuItem(
                              value: (t['id'] ?? email).toString(),
                              child: Text(label, style: AppTypography.bodySm, overflow: TextOverflow.ellipsis),
                            );
                          }),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedTenantFilter = val;
                              _currentPage = 0;
                            });
                            _loadData();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.spaceMd),
          ],

          // Clean Wrap of Filter Buttons (NO sliding horizontal scroll on mobile)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_tabs.length, (index) {
              final isSelected = _activeFilterTab == index;
              return InkWell(
                onTap: () => _onTabSelected(index),
                borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.background,
                    border: Border.all(color: AppColors.primary, width: 1.2),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                  ),
                  child: Text(
                    _tabs[index],
                    style: AppTypography.labelMd.copyWith(
                      color: isSelected ? AppColors.background : AppColors.primary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: AppDimensions.spaceMd),

          // Search & Export Bar Card
          IndustrialCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: IndustrialTextField(
                        controller: _searchCtrl,
                        hintText: 'Search by Bearing ID (e.g. PB-9402)...',
                        prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.primary),
                        onChanged: _onSearchChanged,
                      ),
                    ),
                    const SizedBox(width: AppDimensions.spaceSm),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: AppColors.primary),
                      tooltip: 'Refresh Registry',
                      onPressed: _loadData,
                    ),
                  ],
                ),
                const SizedBox(height: AppDimensions.spaceSm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedBearingIds.isEmpty
                          ? '$totalItems total records found'
                          : '${_selectedBearingIds.length} of $totalItems selected',
                      style: AppTypography.caption,
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (_selectedBearingIds.isNotEmpty)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.background,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                              ),
                            ),
                            onPressed: _showBulkAssignDialog,
                            icon: const Icon(Icons.assignment_outlined, size: 16),
                            label: const Text('Bulk Assign Warranty', style: AppTypography.caption),
                          ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                            ),
                          ),
                          onPressed: _exportTxt,
                          icon: const Icon(Icons.description_outlined, size: 16),
                          label: const Text('TXT', style: AppTypography.caption),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                            ),
                          ),
                          onPressed: _exportCsv,
                          icon: const Icon(Icons.table_chart_outlined, size: 16),
                          label: const Text('CSV', style: AppTypography.caption),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                            ),
                          ),
                          onPressed: _exportWord,
                          icon: const Icon(Icons.article_outlined, size: 16),
                          label: const Text('DOC', style: AppTypography.caption),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spaceMd),

          // Registry Content (Responsive: Table on Desktop, Cards on Mobile)
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_errorMessage != null)
            Center(child: Text(_errorMessage!, style: AppTypography.bodyMd))
          else if (_qrList.isEmpty)
            IndustrialCard(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    children: [
                      const Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.primary),
                      const SizedBox(height: AppDimensions.spaceSm),
                      const Text('No QR records match your criteria.', style: AppTypography.headlineSm),
                      const SizedBox(height: 4),
                      const Text('Try generating QR codes or adjust status filters.', style: AppTypography.bodySm),
                      const SizedBox(height: AppDimensions.spaceMd),
                      IndustrialButton(
                        label: 'GENERATE QR CODES',
                        variant: IndustrialButtonVariant.primary,
                        width: 180,
                        onPressed: () => Navigator.pushNamed(context, AppRoutes.qrBulkGeneration),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 850;

                return Column(
                  children: [
                    if (isDesktop)
                      _buildDesktopTable(pagedList)
                    else
                      _buildMobileCardList(pagedList),

                    const SizedBox(height: AppDimensions.spaceMd),

                    // Pagination Control Bar (Strictly 10 per page)
                    _buildPaginationBar(
                      totalItems: totalItems,
                      startIndex: startIndex,
                      endIndex: endIndex,
                      totalPages: totalPages,
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
      },
    );

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const IndustrialAppBar(title: 'QR Inventory'),
      body: SafeArea(child: content),
    );
  }

  // Desktop Table Layout
  Widget _buildDesktopTable(List<Map<String, dynamic>> pagedList) {
    final allPagedSelected = pagedList.isNotEmpty &&
        pagedList.every((row) => _selectedBearingIds.contains(row['bearing_id'].toString()));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.primary, width: 1.5),
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(AppColors.primary),
            headingTextStyle: const TextStyle(
              color: AppColors.background,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            dataRowMinHeight: 52,
            dataRowMaxHeight: 52,
            columns: [
              DataColumn(
                label: Checkbox(
                  value: allPagedSelected,
                  onChanged: (_) => _toggleSelectAll(pagedList),
                  activeColor: AppColors.background,
                  checkColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.background, width: 1.5),
                ),
              ),
              const DataColumn(label: Text('BEARING ID')),
              const DataColumn(label: Text('MODEL NUMBER')),
              const DataColumn(label: Text('TENANT ALLOCATION')),
              const DataColumn(label: Text('LIFECYCLE STATUS')),
              const DataColumn(label: Text('WARRANTY')),
              const DataColumn(label: Text('ACTIONS')),
            ],
            rows: pagedList.map((row) {
              final id = row['bearing_id'].toString();
              final isSelected = _selectedBearingIds.contains(id);
              final tenantComp = row['company_name']?.toString() ?? '';
              final tenantEmail = row['assigned_customer_email']?.toString() ?? '';
              final facilityCode = row['facility_code']?.toString() ?? '';

              return DataRow(
                selected: isSelected,
                onSelectChanged: (_) => _toggleSelectOne(id),
                cells: [
                  DataCell(
                    Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleSelectOne(id),
                      activeColor: AppColors.primary,
                    ),
                  ),
                  DataCell(Text(id, style: AppTypography.labelMd.copyWith(fontWeight: FontWeight.bold))),
                  DataCell(Text(row['model_number'] ?? 'PBI-6204-ZZ', style: AppTypography.bodySm)),
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          tenantComp.isNotEmpty
                              ? tenantComp
                              : (tenantEmail.isNotEmpty ? tenantEmail : 'PBI Master Stock'),
                          style: AppTypography.labelMd.copyWith(fontSize: 11),
                        ),
                        if (facilityCode.isNotEmpty)
                          Text(
                            'FAC: $facilityCode',
                            style: AppTypography.caption.copyWith(fontSize: 10),
                          ),
                      ],
                    ),
                  ),
                  DataCell(
                    IndustrialStatusBadge(
                      statusText: row['current_lifecycle_state'] ?? 'NOT_ACTIVATED',
                      isPrimary: true,
                    ),
                  ),
                  DataCell(Text('${row['duration_months'] ?? 6} Months', style: AppTypography.bodySm)),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary, size: 20),
                          tooltip: 'Inspect QR Matrix',
                          onPressed: () => _showInspectModal(row),
                        ),
                        IconButton(
                          icon: const Icon(Icons.history_toggle_off, color: AppColors.primary, size: 20),
                          tooltip: 'Inspect Lifecycle & Cycles',
                          onPressed: () => BearingLifecycleInspectorDialog.show(context, id),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // Mobile Clean Card-Based Layout (No sliding table or horizontal overflows)
  Widget _buildMobileCardList(List<Map<String, dynamic>> pagedList) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: pagedList.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final row = pagedList[index];
        final id = row['bearing_id'].toString();
        final isSelected = _selectedBearingIds.contains(id);
        final model = row['model_number'] ?? 'PBI-6204-ZZ';
        final state = row['current_lifecycle_state'] ?? 'NOT_ACTIVATED';
        final duration = row['duration_months'] ?? 6;

        return IndustrialCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: isSelected,
                        onChanged: (_) => _toggleSelectOne(id),
                        activeColor: AppColors.primary,
                      ),
                      Text(id, style: AppTypography.headlineSm),
                    ],
                  ),
                  IndustrialStatusBadge(
                    statusText: state,
                    isPrimary: true,
                  ),
                ],
              ),
              const Divider(color: AppColors.primary, height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('MODEL: $model', style: AppTypography.caption),
                  Text('WARRANTY: $duration MONTHS', style: AppTypography.labelMd),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('WARRANTY: $duration MONTHS', style: AppTypography.labelMd),
                  Text(row['plant_location'] ?? 'Plant 02 — Chakan', style: AppTypography.caption),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.apartment, size: 12, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'TENANT: ${row['company_name'] ?? (row['assigned_customer_email'] ?? 'PBI Master Stock')} • FAC: ${row['facility_code'] ?? 'CHAKAN-01'}',
                      style: AppTypography.caption.copyWith(fontSize: 10, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: IndustrialButton(
                      label: 'INSPECT QR',
                      icon: Icons.qr_code_scanner,
                      variant: IndustrialButtonVariant.primary,
                      onPressed: () => _showInspectModal(row),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: IndustrialButton(
                      label: 'LIFECYCLE',
                      icon: Icons.history_toggle_off,
                      variant: IndustrialButtonVariant.secondary,
                      onPressed: () => BearingLifecycleInspectorDialog.show(context, id),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // Strict Pagination Bar (10 items per page)
  Widget _buildPaginationBar({
    required int totalItems,
    required int startIndex,
    required int endIndex,
    required int totalPages,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.primary, width: 1.5),
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${totalItems > 0 ? (startIndex + 1) : 0}–$endIndex of $totalItems items',
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.first_page, size: 20),
                color: AppColors.primary,
                tooltip: 'First Page',
                onPressed: _currentPage > 0
                    ? () => setState(() => _currentPage = 0)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                color: AppColors.primary,
                tooltip: 'Previous Page',
                onPressed: _currentPage > 0
                    ? () => setState(() => _currentPage--)
                    : null,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                ),
                child: Text(
                  '${_currentPage + 1} / $totalPages',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: AppColors.primary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                color: AppColors.primary,
                tooltip: 'Next Page',
                onPressed: _currentPage < totalPages - 1
                    ? () => setState(() => _currentPage++)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.last_page, size: 20),
                color: AppColors.primary,
                tooltip: 'Last Page',
                onPressed: _currentPage < totalPages - 1
                    ? () => setState(() => _currentPage = totalPages - 1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
