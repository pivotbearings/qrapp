import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../data/models/bearing_item_model.dart';
import '../../data/repositories/item_master_repository.dart';

/// Modal selector for Bearing Item Code in QR Bulk Generation
/// Features:
/// - Real-time search bar
/// - Strict 10-item pagination per page
/// - One-tap selection
/// - Instant inline "+ New Item" creation
class ItemSelectionDialog extends StatefulWidget {
  final String? initialSelectedCode;

  const ItemSelectionDialog({
    super.key,
    this.initialSelectedCode,
  });

  static Future<BearingItemModel?> show(BuildContext context, {String? currentCode}) {
    return showDialog<BearingItemModel>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ItemSelectionDialog(initialSelectedCode: currentCode),
    );
  }

  @override
  State<ItemSelectionDialog> createState() => _ItemSelectionDialogState();
}

class _ItemSelectionDialogState extends State<ItemSelectionDialog> {
  final ItemMasterRepository _repo = ItemMasterRepository();
  final TextEditingController _searchCtrl = TextEditingController();

  int _currentPage = 1;
  static const int _pageSize = 10;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _repo.fetchItemsFromSupabase().then((_) {
      if (mounted) setState(() {});
    });
    _searchCtrl.addListener(() {
      final text = _searchCtrl.text;
      if (text != _searchQuery) {
        setState(() {
          _searchQuery = text;
          _currentPage = 1;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showAddNewItemDialog() {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String? selectedCategory;
    final warrantyCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? localError;

    showDialog(
      context: context,
      builder: (addCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          final categories = _repo.getCategories();

          return AlertDialog(
            backgroundColor: AppColors.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: const BorderSide(color: AppColors.primary, width: 2.0),
            ),
            title: const Text('ADD NEW ITEM MASTER', style: AppTypography.headlineSm),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (localError != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.primary),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Text(localError!, style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: AppDimensions.spaceSm),
                    ],

                    // 1. Item Code (Pill input, No heading, Clear placeholder)
                    TextField(
                      controller: codeCtrl,
                      style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Bearing Item Code (e.g. PBI-6306-2RS) *',
                        hintStyle: AppTypography.bodySm.copyWith(color: AppColors.primary.withOpacity(0.55)),
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
                    const SizedBox(height: AppDimensions.spaceSm),

                    // 2. Product Name / Description (Pill input, No heading, Clear placeholder)
                    TextField(
                      controller: nameCtrl,
                      style: AppTypography.bodyMd,
                      decoration: InputDecoration(
                        hintText: 'Product Name / Description *',
                        hintStyle: AppTypography.bodySm.copyWith(color: AppColors.primary.withOpacity(0.55)),
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
                    const SizedBox(height: AppDimensions.spaceSm),

                    // 3. Dynamic Category Dropdown (Pill dropdown, No heading)
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      isExpanded: true,
                      decoration: InputDecoration(
                        hintText: 'Select Bearing Category *',
                        hintStyle: AppTypography.bodySm.copyWith(color: AppColors.primary.withOpacity(0.55)),
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
                      borderRadius: BorderRadius.circular(20),
                      dropdownColor: AppColors.background,
                      items: categories.map((cat) {
                        return DropdownMenuItem<String>(
                          value: cat,
                          child: Text(cat, style: AppTypography.bodySm),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setModalState(() {
                          selectedCategory = val;
                        });
                      },
                    ),
                    const SizedBox(height: AppDimensions.spaceSm),

                    // 4. Default Warranty in Months (Pill input, No heading, No default value)
                    TextField(
                      controller: warrantyCtrl,
                      keyboardType: TextInputType.number,
                      style: AppTypography.bodyMd,
                      decoration: InputDecoration(
                        hintText: 'Default Warranty Duration in Months (e.g. 6) *',
                        hintStyle: AppTypography.bodySm.copyWith(color: AppColors.primary.withOpacity(0.55)),
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
                    const SizedBox(height: AppDimensions.spaceSm),

                    // 5. Technical Specifications (Pill input, No heading, Clear placeholder)
                    TextField(
                      controller: descCtrl,
                      style: AppTypography.bodyMd,
                      decoration: InputDecoration(
                        hintText: 'Technical Specifications (Optional)',
                        hintStyle: AppTypography.bodySm.copyWith(color: AppColors.primary.withOpacity(0.55)),
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
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(addCtx),
                child: const Text('CANCEL', style: TextStyle(color: AppColors.primary)),
              ),
              IndustrialButton(
                label: 'SAVE ITEM',
                variant: IndustrialButtonVariant.primary,
                width: 130,
                onPressed: () {
                  final code = codeCtrl.text.trim().toUpperCase();
                  final name = nameCtrl.text.trim();
                  if (code.isEmpty || name.isEmpty) {
                    setModalState(() {
                      localError = 'Item Code and Product Name are required.';
                    });
                    return;
                  }
                  if (selectedCategory == null || selectedCategory!.isEmpty) {
                    setModalState(() {
                      localError = 'Please select a Bearing Category.';
                    });
                    return;
                  }
                  final warranty = int.tryParse(warrantyCtrl.text.trim()) ?? 6;

                  final newItem = BearingItemModel(
                    itemCode: code,
                    itemName: name,
                    category: selectedCategory!,
                    defaultWarrantyMonths: warranty,
                    description: descCtrl.text.trim(),
                    createdAt: DateTime.now(),
                  );

                  _repo.addItem(newItem);
                  Navigator.pop(addCtx);
                  setState(() {}); // Refresh list
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paginated = _repo.getDropdownItems(
      page: _currentPage,
      pageSize: _pageSize,
      query: _searchQuery,
    );

    final startItem = paginated.totalCount == 0 ? 0 : (_currentPage - 1) * _pageSize + 1;
    final endItem = (_currentPage * _pageSize).clamp(0, paginated.totalCount);

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isMobile = screenWidth < 600;

    return Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isMobile ? 20 : 28),
        side: const BorderSide(color: AppColors.primary, width: 2.0),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: isMobile ? 16 : 32,
      ),
      child: Container(
        width: isMobile ? double.infinity : 620,
        height: isMobile ? (screenHeight * 0.90).clamp(480.0, 750.0) : 660,
        padding: EdgeInsets.all(isMobile ? 14 : AppDimensions.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isMobile ? 'SELECT ITEM CODE' : 'SELECT BEARING / ITEM CODE',
                        style: isMobile ? AppTypography.labelLg.copyWith(fontWeight: FontWeight.bold) : AppTypography.headlineSm,
                      ),
                      const SizedBox(height: 2),
                      const Text('Item Master Catalog (10 items / page)', style: AppTypography.caption),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.primary),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spaceSm),

            // Search Bar & Add Button Row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: AppTypography.bodyMd,
                    decoration: InputDecoration(
                      hintText: isMobile ? 'Search code, name...' : 'Search by item code, name, category...',
                      hintStyle: AppTypography.caption,
                      prefixIcon: const Icon(Icons.search, color: AppColors.primary, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18, color: AppColors.primary),
                              onPressed: () => _searchCtrl.clear(),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(50),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(50),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(50),
                        borderSide: const BorderSide(color: AppColors.primary, width: 2.0),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _showAddNewItemDialog,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.background,
                    backgroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 14, vertical: 11),
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(isMobile ? 'NEW' : 'NEW ITEM', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spaceSm),

            // Items List (Paginated 10 items)
            Expanded(
              child: paginated.items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 36, color: AppColors.primary),
                          const SizedBox(height: 8),
                          Text('No items match "$_searchQuery"', style: AppTypography.labelMd, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          IndustrialButton(
                            label: 'ADD THIS ITEM CODE',
                            icon: Icons.add,
                            variant: IndustrialButtonVariant.primary,
                            width: 200,
                            onPressed: _showAddNewItemDialog,
                          ),
                        ],
                      ),
                    )
                  : Scrollbar(
                      thumbVisibility: true,
                      child: ListView.separated(
                        padding: const EdgeInsets.only(top: 4, bottom: 4, right: 6),
                        itemCount: paginated.items.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
                          final item = paginated.items[idx];
                          final isSelected = widget.initialSelectedCode == item.itemCode;

                          return InkWell(
                            onTap: () => Navigator.pop(context, item),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isMobile ? 12 : 16,
                                vertical: isMobile ? 10 : 12,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary : AppColors.background,
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: isSelected ? 2.0 : 1.2,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 26,
                                        height: 26,
                                        decoration: BoxDecoration(
                                          color: isSelected ? AppColors.background : AppColors.primary,
                                          borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            Icons.precision_manufacturing,
                                            size: 14,
                                            color: isSelected ? AppColors.primary : AppColors.background,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          item.itemCode,
                                          style: AppTypography.mono.copyWith(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: isSelected ? AppColors.background : AppColors.primary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: isSelected ? AppColors.background : AppColors.primary,
                                          ),
                                          borderRadius: BorderRadius.circular(50),
                                        ),
                                        child: Text(
                                          item.category.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected ? AppColors.background : AppColors.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isSelected ? AppColors.background : AppColors.primary,
                                          borderRadius: BorderRadius.circular(50),
                                        ),
                                        child: Text(
                                          '${item.defaultWarrantyMonths}M',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected ? AppColors.primary : AppColors.background,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  // Product Name with 100% full visibility - no cutoffs!
                                  Text(
                                    item.itemName,
                                    style: AppTypography.bodySm.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: isSelected ? AppColors.background : AppColors.primary,
                                      height: 1.25,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (item.description.isNotEmpty && item.description != item.itemName) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      item.description,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isSelected ? AppColors.background.withValues(alpha: 0.8) : AppColors.primary.withValues(alpha: 0.7),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),

            const SizedBox(height: AppDimensions.spaceSm),
            const Divider(color: AppColors.primary, thickness: 1.0),
            const SizedBox(height: AppDimensions.spaceXs),

            // Pagination Controls Row (10 items / page)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    paginated.totalCount == 0
                        ? 'No items'
                        : isMobile
                            ? '$startItem–$endItem of ${paginated.totalCount}'
                            : 'Showing $startItem–$endItem of ${paginated.totalCount} (Page $_currentPage/${paginated.totalPages})',
                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: paginated.hasPrevious
                          ? () => setState(() => _currentPage--)
                          : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: const Size(36, 30),
                      ),
                      child: const Text('PREV', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      onPressed: paginated.hasNext
                          ? () => setState(() => _currentPage++)
                          : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: const Size(36, 30),
                      ),
                      child: const Text('NEXT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
