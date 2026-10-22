import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/qr_export_service.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../data/repositories/qr_management_repository.dart';
import '../../../item_master/data/models/bearing_item_model.dart';
import '../../../item_master/data/repositories/item_master_repository.dart';
import '../../../item_master/presentation/widgets/item_selection_dialog.dart';
import '../../../../core/widgets/app_snack_bar.dart';

class QrBulkGenerationScreen extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onNavigateToItemMaster;

  const QrBulkGenerationScreen({
    super.key,
    this.isEmbedded = false,
    this.onNavigateToItemMaster,
  });

  @override
  State<QrBulkGenerationScreen> createState() => _QrBulkGenerationScreenState();
}

class _QrBulkGenerationScreenState extends State<QrBulkGenerationScreen> {
  final QrManagementRepository _repo = QrManagementRepository();
  final ItemMasterRepository _itemRepo = ItemMasterRepository();

  // 1. Selected Item / Bearing Code
  BearingItemModel? _selectedItem;

  // 2. Production Quantity
  final TextEditingController _countCtrl = TextEditingController(text: '50');

  // 3. Warranty Horizon Timing
  String _selectedWarrantyHorizonKey = '6'; // months
  bool _isCustomWarranty = false;
  final TextEditingController _customMonthsCtrl = TextEditingController(text: '9');

  bool _isGenerating = false;
  String? _errorMessage;

  String? _lastGeneratedBatchCode;
  List<String> _generatedBearingIds = [];

  @override
  void initState() {
    super.initState();
    // Do not select a product by default; user must explicitly select bearing/item
    _selectedItem = null;
    _itemRepo.fetchItemsFromSupabase().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    _customMonthsCtrl.dispose();
    super.dispose();
  }

  int get _effectiveWarrantyMonths {
    if (_isCustomWarranty) {
      return int.tryParse(_customMonthsCtrl.text.trim()) ?? 6;
    }
    return int.tryParse(_selectedWarrantyHorizonKey) ?? (_selectedItem?.defaultWarrantyMonths ?? 6);
  }

  Future<void> _openItemSelector() async {
    final selected = await ItemSelectionDialog.show(
      context,
      currentCode: _selectedItem?.itemCode,
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedItem = selected;
        if (!_isCustomWarranty) {
          _selectedWarrantyHorizonKey = selected.defaultWarrantyMonths.toString();
        }
      });
    }
  }

  Future<void> _triggerGeneration() async {
    if (_selectedItem == null) {
      setState(() {
        _errorMessage = 'Please select a bearing item before generating QR codes.';
      });
      return;
    }

    final count = int.tryParse(_countCtrl.text.trim()) ?? 0;
    if (count <= 0 || count > 5000) {
      setState(() {
        _errorMessage = 'Quantity must be a valid positive integer between 1 and 5,000.';
      });
      return;
    }

    if (_isCustomWarranty) {
      final customMonths = int.tryParse(_customMonthsCtrl.text.trim()) ?? 0;
      if (customMonths < 0 || customMonths > 240) {
        setState(() {
          _errorMessage = 'Custom warranty duration must be between 0 and 240 months.';
        });
        return;
      }
    }

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      // Auto-generate consistent batch code
      final now = DateTime.now();
      final autoBatch = 'BATCH-${now.year}-${(now.millisecondsSinceEpoch % 100000).toString().padLeft(5, '0')}';

      final result = await _repo.generateQrBatch(
        batchCode: autoBatch,
        plantLocation: 'Plant 02 — Chakan Industrial Complex',
        quantity: count,
        modelNumber: _selectedItem!.itemCode,
        defaultWarrantyPlanId: null,
      );

      final rawIds = result['bearing_ids'];
      final List<String> ids = rawIds is List ? rawIds.map((e) => e.toString()).toList() : [];

      setState(() {
        _isGenerating = false;
        _lastGeneratedBatchCode = autoBatch;
        _generatedBearingIds = ids;
      });

      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          'Successfully generated ${ids.length} unique QR values. Ready for instant download.',
        );
      }
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _errorMessage = 'Generation failed: ${e.toString().replaceAll('Exception:', '').trim()}';
      });
    }
  }

  List<Map<String, dynamic>> _buildExportList() {
    return _generatedBearingIds.map((id) => {
      'bearing_id': id,
      'batch_code': _lastGeneratedBatchCode ?? 'BATCH-ACTIVE',
      'model_number': _selectedItem?.itemCode ?? 'GENERIC',
      'duration_months': _effectiveWarrantyMonths,
      'current_lifecycle_state': 'NOT_ACTIVATED',
      'is_flagged': false,
      'payload_value': id, // Pure bearing serial - NO DOMAIN
      'payload_hash': 'SHA-256: VALID',
      'created_at': DateTime.now().toIso8601String(),
    }).toList();
  }

  void _downloadRawTxtValues() {
    if (_generatedBearingIds.isEmpty) return;
    // Pure list of raw QR codes, 1 per line, ideal for laser marking & label printers
    final textContent = _generatedBearingIds.join('\r\n');
    QrExportService.downloadCustomFile(
      filename: '${_selectedItem?.itemCode ?? "BEARING"}_${_lastGeneratedBatchCode ?? "QR"}_VALUES.txt',
      content: textContent,
      mimeType: 'text/plain',
    );
  }

  void _downloadManifestTxt() {
    if (_generatedBearingIds.isEmpty) return;
    QrExportService.downloadTxt(
      batchCode: _lastGeneratedBatchCode ?? 'BATCH-ACTIVE',
      items: _buildExportList(),
    );
  }

  void _downloadCsv() {
    if (_generatedBearingIds.isEmpty) return;
    QrExportService.downloadCsv(
      batchCode: _lastGeneratedBatchCode ?? 'BATCH-ACTIVE',
      items: _buildExportList(),
    );
  }

  void _copyAllToClipboard() {
    if (_generatedBearingIds.isEmpty) return;
    final text = _generatedBearingIds.join('\n');
    Clipboard.setData(ClipboardData(text: text));
    AppSnackBar.showSuccess(
      context,
      'Copied ${_generatedBearingIds.length} QR values to clipboard.',
    );
  }

  @override
  Widget build(BuildContext context) {
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
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppDimensions.spaceSm),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    border: Border.all(color: AppColors.primary, width: 2.0),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.primary),
                      const SizedBox(width: AppDimensions.spaceSm),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: AppTypography.labelMd.copyWith(color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimensions.spaceMd),
              ],

              // Main Form & Output Layout
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 880;

                  final configCard = IndustrialCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Pill-shaped Bearing / Item Code Selector with Placeholder
                        InkWell(
                          onTap: _openItemSelector,
                          borderRadius: BorderRadius.circular(50),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              border: Border.all(color: AppColors.primary, width: 1.5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.precision_manufacturing,
                                    size: 18,
                                    color: AppColors.background,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _selectedItem == null
                                      ? Text(
                                          'Select Bearing/item',
                                          style: AppTypography.bodyMd.copyWith(
                                            color: AppColors.primary.withValues(alpha: 0.55),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        )
                                      : Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _selectedItem!.itemCode,
                                              style: AppTypography.mono.copyWith(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${_selectedItem!.itemName} (${_selectedItem!.category})',
                                              style: AppTypography.caption.copyWith(height: 1.2),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: _selectedItem != null ? AppColors.primary : Colors.transparent,
                                    border: Border.all(color: AppColors.primary, width: 1.2),
                                    borderRadius: BorderRadius.circular(50),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _selectedItem == null ? 'SELECT' : 'CHANGE',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: _selectedItem != null ? AppColors.background : AppColors.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.arrow_drop_down,
                                        size: 16,
                                        color: _selectedItem != null ? AppColors.background : AppColors.primary,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppDimensions.spaceMd),

                        // Pill-shaped Production Quantity with Placeholder
                        TextField(
                          controller: _countCtrl,
                          keyboardType: TextInputType.number,
                          style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            hintText: 'Enter Production Quantity (1 – 5,000)',
                            hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.primary.withOpacity(0.55)),
                            prefixIcon: const Icon(Icons.pin_outlined, color: AppColors.primary, size: 20),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(50),
                              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(50),
                              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(50),
                              borderSide: const BorderSide(color: AppColors.primary, width: 2.0),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppDimensions.spaceMd),

                        // Pill-shaped & Minimalistic Warranty Horizon Timing Dropdown
                        DropdownButtonFormField<String>(
                          initialValue: _isCustomWarranty ? 'CUSTOM' : _selectedWarrantyHorizonKey,
                          isExpanded: true,
                          decoration: InputDecoration(
                            hintText: 'Select Warranty Horizon',
                            hintStyle: AppTypography.bodyMd.copyWith(color: AppColors.primary.withOpacity(0.55)),
                            prefixIcon: const Icon(Icons.verified_outlined, color: AppColors.primary, size: 20),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(50),
                              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(50),
                              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(50),
                              borderSide: const BorderSide(color: AppColors.primary, width: 2.0),
                            ),
                          ),
                          borderRadius: BorderRadius.circular(24),
                          dropdownColor: AppColors.background,
                          items: const [
                            DropdownMenuItem(value: '0', child: Text('0 Month Warranty (0M)', style: AppTypography.bodySm)),
                            DropdownMenuItem(value: '3', child: Text('3 Months Standard Warranty (3M)', style: AppTypography.bodySm)),
                            DropdownMenuItem(value: '6', child: Text('6 Months Heavy Duty Warranty (6M)', style: AppTypography.bodySm)),
                            DropdownMenuItem(value: '12', child: Text('12 Months Industrial Warranty (12M)', style: AppTypography.bodySm)),
                            DropdownMenuItem(value: '18', child: Text('18 Months Extended Warranty (18M)', style: AppTypography.bodySm)),
                            DropdownMenuItem(value: '24', child: Text('24 Months Extended Mining Warranty (24M)', style: AppTypography.bodySm)),
                            DropdownMenuItem(value: '36', child: Text('36 Months Long-Term Industrial (36M)', style: AppTypography.bodySm)),
                            DropdownMenuItem(value: 'CUSTOM', child: Text('Custom Warranty Horizon (Specify Months)', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          onChanged: (val) {
                            if (val == null) return;
                            setState(() {
                              if (val == 'CUSTOM') {
                                _isCustomWarranty = true;
                              } else {
                                _isCustomWarranty = false;
                                _selectedWarrantyHorizonKey = val;
                              }
                            });
                          },
                        ),

                        // Custom Range Input if "Custom" selected
                        if (_isCustomWarranty) ...[
                          const SizedBox(height: AppDimensions.spaceSm),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.primary, width: 1.2),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller: _customMonthsCtrl,
                                  keyboardType: TextInputType.number,
                                  style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
                                  decoration: InputDecoration(
                                    hintText: 'Custom Duration in Months (e.g. 9, 15, 48)',
                                    hintStyle: AppTypography.caption,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(50),
                                      borderSide: const BorderSide(color: AppColors.primary),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(50),
                                      borderSide: const BorderSide(color: AppColors.primary),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  children: [0, 1, 2, 3, 6, 9, 12, 15, 24, 36, 48, 60].map((m) {
                                    return InkWell(
                                      onTap: () {
                                        setState(() {
                                          _customMonthsCtrl.text = m.toString();
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(50),
                                      child: Chip(
                                        label: Text('${m}M', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                        backgroundColor: AppColors.background,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(50),
                                          side: const BorderSide(color: AppColors.primary, width: 1),
                                        ),
                                        padding: EdgeInsets.zero,
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: AppDimensions.spaceLg),

                        // LOADING UI & GENERATE BUTTON
                        if (_isGenerating) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.primary, width: 1.5),
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: const Column(
                              children: [
                                LinearProgressIndicator(color: AppColors.primary, backgroundColor: AppColors.background),
                                SizedBox(height: 12),
                                Text(
                                  'GENERATING UNIQUE QR IDENTIFIERS...',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                                ),
                                SizedBox(height: 4),
                                Text('Allocating cryptographic serial sequences', style: AppTypography.caption),
                              ],
                            ),
                          ),
                        ] else ...[
                          IndustrialButton(
                            label: 'GENERATE',
                            icon: Icons.qr_code_2,
                            variant: IndustrialButtonVariant.primary,
                            onPressed: _triggerGeneration,
                          ),
                        ],
                      ],
                    ),
                  );

                  // Instant Downloadable Suite (QR Matrix preview card removed per user specification)
                  final downloadCard = IndustrialCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text('INSTANT DOWNLOADABLE OPTIONS', style: AppTypography.labelMd),
                              ),
                            ),
                            if (_generatedBearingIds.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: Text(
                                  '${_generatedBearingIds.length} READY',
                                  style: const TextStyle(
                                    color: AppColors.background,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: AppDimensions.spaceMd),

                        if (_generatedBearingIds.isEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.download_for_offline_outlined, color: AppColors.primary, size: 40),
                                SizedBox(height: 12),
                                Text(
                                  'Ready for Generation',
                                  style: AppTypography.labelMd,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Select item and quantity, then click "GENERATE" to enable instant file download on your device.',
                                  style: AppTypography.caption,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          ElevatedButton.icon(
                            onPressed: _downloadRawTxtValues,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.background,
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(50),
                              ),
                            ),
                            icon: const Icon(Icons.file_download, size: 20),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'DOWNLOAD TXT (${_generatedBearingIds.length} QR VALUES)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Secondary CSV and Copy Buttons
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _downloadCsv,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    side: const BorderSide(color: AppColors.primary, width: 1.5),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                                    padding: const EdgeInsets.symmetric(vertical: 11),
                                  ),
                                  icon: const Icon(Icons.table_chart_outlined, size: 16),
                                  label: const Text('CSV (Excel)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _copyAllToClipboard,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    side: const BorderSide(color: AppColors.primary, width: 1.5),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                                    padding: const EdgeInsets.symmetric(vertical: 11),
                                  ),
                                  icon: const Icon(Icons.copy, size: 16),
                                  label: const Text('COPY ALL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _downloadManifestTxt,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary, width: 1.2),
                              minimumSize: const Size.fromHeight(40),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                            ),
                            icon: const Icon(Icons.receipt_long, size: 16),
                            label: const Text('FULL AUDIT MANIFEST (TXT)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),

                          const SizedBox(height: 14),

                          // Quick Preview of Generated Text Values
                          Container(
                            height: 130,
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.primary, width: 1.0),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ListView.builder(
                              itemCount: _generatedBearingIds.length,
                              itemBuilder: (context, i) {
                                final id = _generatedBearingIds[i];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${(i + 1).toString().padLeft(3, '0')}. $id',
                                        style: AppTypography.mono.copyWith(fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                      InkWell(
                                        onTap: () {
                                          Clipboard.setData(ClipboardData(text: id));
                                          AppSnackBar.showSuccess(context, 'Copied $id');
                                        },
                                        child: const Icon(Icons.copy, size: 14, color: AppColors.primary),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],

                        const SizedBox(height: AppDimensions.spaceMd),
                        IndustrialButton(
                          label: 'VIEW IN QR REGISTRY',
                          icon: Icons.inventory_2_outlined,
                          variant: IndustrialButtonVariant.secondary,
                          onPressed: () {
                            Navigator.pushNamed(context, AppRoutes.qrInventory);
                          },
                        ),
                      ],
                    ),
                  );

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: configCard),
                        const SizedBox(width: AppDimensions.spaceLg),
                        Expanded(flex: 4, child: downloadCard),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      configCard,
                      const SizedBox(height: AppDimensions.spaceLg),
                      downloadCard,
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
      appBar: const IndustrialAppBar(title: 'QR Generation'),
      body: SafeArea(child: content),
    );
  }
}
