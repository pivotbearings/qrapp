import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/qr_export_service.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../qr_generation/data/repositories/qr_management_repository.dart';
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
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

  List<Map<String, dynamic>> _filesList = [];
  final Set<String> _selectedBatchCodes = {};
  bool _isLoading = true;
  bool _isDownloadingWhole = false;
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

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final auth = AuthController.instance;
      final effectiveTenant = !auth.isAdmin ? (auth.userId ?? auth.userEmail) : null;

      final files = await _repo.fetchGeneratedFilesManifest(
        searchQuery: _searchCtrl.text.trim(),
        customerId: effectiveTenant,
      );

      if (mounted) {
        setState(() {
          _filesList = files;
          _selectedBatchCodes.clear();
          _currentPage = 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load QR files manifest: $e';
        });
      }
    }
  }

  void _toggleSelectAll(List<Map<String, dynamic>> pagedList) {
    setState(() {
      final allSelected = pagedList.isNotEmpty &&
          pagedList.every((row) => _selectedBatchCodes.contains(row['batch_code'].toString()));
      if (allSelected) {
        for (final row in pagedList) {
          _selectedBatchCodes.remove(row['batch_code'].toString());
        }
      } else {
        for (final row in pagedList) {
          _selectedBatchCodes.add(row['batch_code'].toString());
        }
      }
    });
  }

  void _toggleSelectOne(String batchCode) {
    setState(() {
      if (_selectedBatchCodes.contains(batchCode)) {
        _selectedBatchCodes.remove(batchCode);
      } else {
        _selectedBatchCodes.add(batchCode);
      }
    });
  }

  /// Downloads single-column QR values for a specific batch file
  void _downloadBatchFile(Map<String, dynamic> file, String ext) {
    final batchCode = file['batch_code']?.toString() ?? 'BATCH';
    final List<dynamic> qrValues = (file['qr_values'] as List<dynamic>?) ?? [];
    final DateTime createdAt = file['created_at'] is DateTime
        ? file['created_at'] as DateTime
        : DateTime.now();

    if (qrValues.isEmpty) {
      AppSnackBar.showError(context, 'This batch has no QR values to download.');
      return;
    }

    if (ext.toLowerCase() == 'csv') {
      QrExportService.downloadCsv(
        batchCode: batchCode,
        items: qrValues,
        timestamp: createdAt,
      );
    } else {
      QrExportService.downloadTxt(
        batchCode: batchCode,
        items: qrValues,
        timestamp: createdAt,
      );
    }

    AppSnackBar.showSuccess(
      context,
      'Downloaded ${qrValues.length} QR values from $batchCode (.${ext.toUpperCase()})',
    );
  }

  /// Copies all QR values of a batch to clipboard
  void _copyBatchQrValues(Map<String, dynamic> file) {
    final List<dynamic> qrValues = (file['qr_values'] as List<dynamic>?) ?? [];
    if (qrValues.isEmpty) {
      AppSnackBar.showError(context, 'No QR values to copy.');
      return;
    }
    final text = qrValues.map((v) => v.toString().trim()).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    AppSnackBar.showSuccess(
      context,
      'Copied ${qrValues.length} QR values from ${file['batch_code']} to clipboard.',
    );
  }

  /// Downloads all QR values across selected batches or whole database
  Future<void> _downloadSelectedOrWhole(String ext) async {
    if (_isDownloadingWhole) return;
    setState(() => _isDownloadingWhole = true);

    try {
      List<String> targetValues = [];
      String label = '';

      if (_selectedBatchCodes.isNotEmpty) {
        final selectedFiles = _filesList
            .where((f) => _selectedBatchCodes.contains(f['batch_code']?.toString()))
            .toList();
        for (final f in selectedFiles) {
          final qrs = (f['qr_values'] as List<dynamic>?) ?? [];
          for (final q in qrs) {
            targetValues.add(q.toString().trim());
          }
        }
        label = '${_selectedBatchCodes.length} selected files (${targetValues.length} QRs)';
      } else {
        final auth = AuthController.instance;
        final effectiveTenant = !auth.isAdmin ? (auth.userId ?? auth.userEmail) : null;
        final allQrs = await _repo.fetchAllRegistryQrValues(customerId: effectiveTenant);
        targetValues = allQrs.map((e) => e.toString().trim()).toList();
        label = 'whole registry (${targetValues.length} QRs)';
      }

      if (targetValues.isEmpty) {
        if (mounted) {
          AppSnackBar.showError(context, 'No QR records found to download.');
        }
        return;
      }

      final now = DateTime.now();
      if (ext.toLowerCase() == 'csv') {
        QrExportService.downloadWholeFileCsv(items: targetValues, timestamp: now);
      } else {
        QrExportService.downloadWholeFileTxt(items: targetValues, timestamp: now);
      }

      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          'Downloaded $label strictly with row-by-row QR values.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'Download failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloadingWhole = false);
      }
    }
  }

  /// Preview modal to view the QR values inside a generated file
  void _showFilePreviewModal(Map<String, dynamic> file) {
    final batchCode = file['batch_code']?.toString() ?? 'BATCH';
    final List<dynamic> qrValues = (file['qr_values'] as List<dynamic>?) ?? [];
    final DateTime createdAt = file['created_at'] is DateTime
        ? file['created_at'] as DateTime
        : DateTime.now();
    final modelNumber = file['model_number']?.toString() ?? 'PBI-6204-ZZ';

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
              child: const Icon(Icons.folder_zip_outlined, color: AppColors.background, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    batchCode,
                    style: AppTypography.headlineSm.copyWith(color: AppColors.primary),
                  ),
                  Text(
                    'Generated: ${_dateFormat.format(createdAt)} • Model: $modelNumber',
                    style: AppTypography.caption.copyWith(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Single-Column QR Values in this file (${qrValues.length} total):',
                style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.primary, width: 1.2),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                  ),
                  child: qrValues.isEmpty
                      ? const Center(child: Text('No QR values recorded in this file.'))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: qrValues.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final val = qrValues[idx].toString();
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 32,
                                    child: Text(
                                      '${idx + 1}.',
                                      style: AppTypography.caption.copyWith(color: Colors.black45),
                                    ),
                                  ),
                                  Expanded(
                                    child: SelectableText(
                                      val,
                                      style: AppTypography.labelMd.copyWith(
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.primary),
                                    tooltip: 'Copy',
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: val));
                                      AppSnackBar.showSuccess(context, 'Copied $val');
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE', style: TextStyle(color: AppColors.primary)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _downloadBatchFile(file, 'csv');
            },
            icon: const Icon(Icons.file_download, size: 16),
            label: const Text('DOWNLOAD CSV'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.background,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _downloadBatchFile(file, 'txt');
            },
            icon: const Icon(Icons.file_download_outlined, size: 16),
            label: const Text('DOWNLOAD TXT'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pagination calculation
    final totalItems = _filesList.length;
    final totalPages = (totalItems == 0) ? 1 : ((totalItems + _pageSize - 1) ~/ _pageSize);
    if (_currentPage >= totalPages && totalPages > 0) {
      _currentPage = totalPages - 1;
    }
    if (_currentPage < 0) {
      _currentPage = 0;
    }

    final startIndex = _currentPage * _pageSize;
    final endIndex = (startIndex + _pageSize > totalItems) ? totalItems : (startIndex + _pageSize);
    final pagedList = (totalItems > 0) ? _filesList.sublist(startIndex, endIndex) : <Map<String, dynamic>>[];

    int totalQrCount = 0;
    for (final f in _filesList) {
      totalQrCount += (f['total_quantity'] as num?)?.toInt() ?? (f['qr_values'] as List?)?.length ?? 0;
    }

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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(child: AdminViewHeader(title: 'QR Registry & Generated Files')),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
                    tooltip: 'Refresh Files List',
                    onPressed: _loadData,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Generated QR batch files with exact generation date & time. Download clean single-column QR files ready for laser marking and industrial operations.',
                style: AppTypography.caption.copyWith(color: Colors.black87),
              ),
              const SizedBox(height: AppDimensions.spaceMd),

              // Filter, Search, and Action Header
              Container(
                padding: const EdgeInsets.all(AppDimensions.spaceSm),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  border: Border.all(color: AppColors.primary, width: 1.5),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            decoration: InputDecoration(
                              hintText: 'Search by File/Batch code, Model, or QR Value...',
                              prefixIcon: const Icon(Icons.search, color: AppColors.primary, size: 20),
                              suffixIcon: _searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        _loadData();
                                      },
                                    )
                                  : null,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                                borderSide: const BorderSide(color: AppColors.primary),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                                borderSide: const BorderSide(color: AppColors.primary, width: 2.0),
                              ),
                            ),
                            onSubmitted: (_) => _loadData(),
                          ),
                        ),
                        const SizedBox(width: AppDimensions.spaceSm),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.background,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                            ),
                          ),
                          onPressed: _loadData,
                          child: const Text('SEARCH'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.spaceSm),

                    // Metrics and Global Download Toolbar
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                              ),
                              child: Text(
                                '${_filesList.length} Files ($totalQrCount Total QRs)',
                                style: const TextStyle(
                                  color: AppColors.background,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (_selectedBatchCodes.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE65100),
                                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                                ),
                                child: Text(
                                  '${_selectedBatchCodes.length} Files Selected',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            // Dedicated "DOWNLOAD WHOLE FILE (CSV)" button
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.background,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                                ),
                              ),
                              onPressed: _isDownloadingWhole ? null : () => _downloadSelectedOrWhole('csv'),
                              icon: _isDownloadingWhole
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
                                    )
                                  : const Icon(Icons.file_download, size: 16),
                              label: Text(
                                _selectedBatchCodes.isNotEmpty
                                    ? 'DOWNLOAD SELECTED (CSV)'
                                    : 'DOWNLOAD WHOLE FILE (CSV)',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                              ),
                            ),
                            // Dedicated "DOWNLOAD WHOLE FILE (TXT)" button
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.background,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                                ),
                              ),
                              onPressed: _isDownloadingWhole ? null : () => _downloadSelectedOrWhole('txt'),
                              icon: const Icon(Icons.file_download_outlined, size: 16),
                              label: Text(
                                _selectedBatchCodes.isNotEmpty
                                    ? 'DOWNLOAD SELECTED (TXT)'
                                    : 'DOWNLOAD WHOLE FILE (TXT)',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                              ),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(color: AppColors.primary),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                                ),
                              ),
                              onPressed: () => Navigator.pushNamed(context, AppRoutes.qrBulkGeneration),
                              icon: const Icon(Icons.add_circle_outline, size: 16),
                              label: const Text('GENERATE QR CODES', style: AppTypography.caption),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppDimensions.spaceMd),

              // Files Manifest Content
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(48),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (_errorMessage != null)
                Center(child: Text(_errorMessage!, style: AppTypography.bodyMd))
              else if (_filesList.isEmpty)
                IndustrialCard(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        children: [
                          const Icon(Icons.folder_off_outlined, size: 48, color: AppColors.primary),
                          const SizedBox(height: AppDimensions.spaceSm),
                          const Text('No generated QR files match your criteria.', style: AppTypography.headlineSm),
                          const SizedBox(height: 4),
                          const Text('Generate your first batch of QR codes to populate files.', style: AppTypography.bodySm),
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

                        // Pagination Control Bar (Strictly 10 files per page)
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
      appBar: const IndustrialAppBar(title: 'QR Registry & Files'),
      body: SafeArea(child: content),
    );
  }

  // Desktop Table Layout: Strictly shows Files with Generation Date & Time and Downloadable Options
  Widget _buildDesktopTable(List<Map<String, dynamic>> pagedList) {
    final allPagedSelected = pagedList.isNotEmpty &&
        pagedList.every((row) => _selectedBatchCodes.contains(row['batch_code'].toString()));

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
            // CRITICAL: showCheckboxColumn set to false ensures Flutter DOES NOT inject an automatic duplicate checkbox column
            showCheckboxColumn: false,
            headingRowColor: WidgetStateProperty.all(AppColors.primary),
            headingTextStyle: const TextStyle(
              color: AppColors.background,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            dataRowMinHeight: 56,
            dataRowMaxHeight: 56,
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
              const DataColumn(label: Text('FILE / BATCH')),
              const DataColumn(label: Text('GENERATION DATE & TIME')),
              const DataColumn(label: Text('QR CODES')),
              const DataColumn(label: Text('MODEL / SPEC')),
              const DataColumn(label: Text('DOWNLOAD FORMAT OPTIONS (QR VALUE ONLY)')),
            ],
            rows: pagedList.map((row) {
              final batchCode = row['batch_code'].toString();
              final isSelected = _selectedBatchCodes.contains(batchCode);
              final DateTime createdAt = row['created_at'] is DateTime
                  ? row['created_at'] as DateTime
                  : DateTime.now();
              final count = (row['total_quantity'] as num?)?.toInt() ?? (row['qr_values'] as List?)?.length ?? 0;
              final model = row['model_number']?.toString() ?? 'PBI-6204-ZZ';

              return DataRow(
                selected: isSelected,
                cells: [
                  DataCell(
                    Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleSelectOne(batchCode),
                      activeColor: AppColors.primary,
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.description_outlined, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              batchCode,
                              style: AppTypography.labelMd.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                            Text(
                              'QR_Batch_$batchCode.csv',
                              style: AppTypography.caption.copyWith(fontSize: 10, color: Colors.black54),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule, size: 15, color: Colors.black54),
                        const SizedBox(width: 6),
                        Text(
                          _dateFormat.format(createdAt),
                          style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        border: Border.all(color: const Color(0xFF2563EB), width: 1.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$count QR Codes',
                        style: const TextStyle(
                          color: Color(0xFF1E40AF),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(model, style: AppTypography.labelMd),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // CSV Download Option
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.background,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                            ),
                          ),
                          onPressed: () => _downloadBatchFile(row, 'csv'),
                          icon: const Icon(Icons.file_download, size: 14),
                          label: const Text('CSV', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 6),
                        // TXT Download Option
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.background,
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            elevation: 0,
                            side: const BorderSide(color: AppColors.primary, width: 1.2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                            ),
                          ),
                          onPressed: () => _downloadBatchFile(row, 'txt'),
                          icon: const Icon(Icons.file_download_outlined, size: 14),
                          label: const Text('TXT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 4),
                        // Copy All Values
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, color: AppColors.primary, size: 18),
                          tooltip: 'Copy all QR values to clipboard',
                          onPressed: () => _copyBatchQrValues(row),
                        ),
                        // Preview Values
                        IconButton(
                          icon: const Icon(Icons.visibility_outlined, color: AppColors.primary, size: 18),
                          tooltip: 'Preview QR values in this file',
                          onPressed: () => _showFilePreviewModal(row),
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

  // Mobile Clean Card-Based Layout for Generated Files
  Widget _buildMobileCardList(List<Map<String, dynamic>> pagedList) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: pagedList.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final row = pagedList[index];
        final batchCode = row['batch_code'].toString();
        final isSelected = _selectedBatchCodes.contains(batchCode);
        final DateTime createdAt = row['created_at'] is DateTime
            ? row['created_at'] as DateTime
            : DateTime.now();
        final count = (row['total_quantity'] as num?)?.toInt() ?? (row['qr_values'] as List?)?.length ?? 0;
        final model = row['model_number']?.toString() ?? 'PBI-6204-ZZ';

        return IndustrialCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleSelectOne(batchCode),
                          activeColor: AppColors.primary,
                        ),
                        const Icon(Icons.folder_zip_outlined, color: AppColors.primary, size: 20),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            batchCode,
                            style: AppTypography.headlineSm,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      border: Border.all(color: const Color(0xFF2563EB)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$count QRs',
                      style: const TextStyle(color: Color(0xFF1E40AF), fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ],
              ),
              const Divider(color: AppColors.primary, height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.schedule, size: 14, color: Colors.black54),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _dateFormat.format(createdAt),
                            style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('MODEL: $model', style: AppTypography.caption),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.background,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      elevation: 0,
                    ),
                    onPressed: () => _downloadBatchFile(row, 'csv'),
                    icon: const Icon(Icons.file_download, size: 14),
                    label: const Text('DOWNLOAD CSV', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.background,
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      elevation: 0,
                    ),
                    onPressed: () => _downloadBatchFile(row, 'txt'),
                    icon: const Icon(Icons.file_download_outlined, size: 14),
                    label: const Text('DOWNLOAD TXT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, color: AppColors.primary, size: 18),
                    tooltip: 'Copy',
                    onPressed: () => _copyBatchQrValues(row),
                  ),
                  IconButton(
                    icon: const Icon(Icons.visibility_outlined, color: AppColors.primary, size: 18),
                    tooltip: 'Preview',
                    onPressed: () => _showFilePreviewModal(row),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // Strict Pagination Bar (10 files per page)
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
            'Showing ${totalItems > 0 ? (startIndex + 1) : 0}–$endIndex of $totalItems files',
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.first_page, size: 20),
                color: AppColors.primary,
                tooltip: 'First Page',
                onPressed: _currentPage > 0 ? () => setState(() => _currentPage = 0) : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                color: AppColors.primary,
                tooltip: 'Previous Page',
                onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
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
                onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
              ),
              IconButton(
                icon: const Icon(Icons.last_page, size: 20),
                color: AppColors.primary,
                tooltip: 'Last Page',
                onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage = totalPages - 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
