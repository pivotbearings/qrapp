import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../data/models/bearing_item_model.dart';
import '../../data/repositories/item_master_repository.dart';
import '../../../admin_dashboard/presentation/widgets/admin_view_header.dart';

/// Admin View for managing the Bearing Item Master Catalog
/// Strictly paginated with 20 items per page
class AdminItemMasterView extends StatefulWidget {
  const AdminItemMasterView({super.key});

  @override
  State<AdminItemMasterView> createState() => _AdminItemMasterViewState();
}

class _AdminItemMasterViewState extends State<AdminItemMasterView> {
  final ItemMasterRepository _repo = ItemMasterRepository();
  final TextEditingController _searchCtrl = TextEditingController();

  int _currentPage = 1;
  static const int _pageSize = 10;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _repo.loadFromLocalStorage().then((_) {
      if (mounted) setState(() {});
      _repo.fetchItemsFromSupabase().then((_) {
        if (mounted) setState(() {});
      });
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

  void _showCategoryMasterDialog() {
    final catCtrl = TextEditingController();
    String? catError;

    showDialog(
      context: context,
      builder: (catCtx) => StatefulBuilder(
        builder: (context, setCatState) {
          final categories = _repo.getCategories();

          return AlertDialog(
            backgroundColor: AppColors.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: const BorderSide(color: AppColors.primary, width: 2.0),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.category_outlined, color: AppColors.primary, size: 22),
                    SizedBox(width: 8),
                    Text('CATEGORY MASTER', style: AppTypography.headlineSm),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.primary),
                  onPressed: () => Navigator.pop(catCtx),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Manage approved bearing categories for the engineering catalog.',
                    style: AppTypography.caption,
                  ),
                  const SizedBox(height: AppDimensions.spaceMd),

                  if (catError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        border: Border.all(color: AppColors.primary),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Text(catError!, style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: AppDimensions.spaceSm),
                  ],

                  // Add Category Input Row (Pill-shaped)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: catCtrl,
                          style: AppTypography.bodyMd,
                          decoration: InputDecoration(
                            hintText: 'Enter category name (e.g. Thrust Bearing)...',
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
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(50),
                              borderSide: const BorderSide(color: AppColors.primary, width: 2.0),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IndustrialButton(
                        label: 'ADD',
                        icon: Icons.add,
                        variant: IndustrialButtonVariant.primary,
                        width: 90,
                        onPressed: () async {
                          final name = catCtrl.text.trim();
                          if (name.isEmpty) {
                            setCatState(() => catError = 'Please enter a category name');
                            return;
                          }
                          await _repo.addCategory(name);
                          catCtrl.clear();
                          setCatState(() => catError = null);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimensions.spaceLg),

                  const Text('EXISTING CATEGORIES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  const SizedBox(height: 10),

                  // Category Pills Wrap
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: categories.map((cat) {
                          final count = _repo.getAllItems().where((it) => it.category.toUpperCase() == cat.toUpperCase()).length;

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              border: Border.all(color: AppColors.primary, width: 1.2),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  cat,
                                  style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$count',
                                    style: const TextStyle(
                                      color: AppColors.background,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () async {
                                    await _repo.deleteCategory(cat);
                                    setCatState(() {});
                                    setState(() {});
                                  },
                                  child: const Icon(Icons.close, size: 14, color: AppColors.primary),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(catCtx),
                child: const Text('DONE', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddOrEditDialog({BearingItemModel? itemToEdit}) {
    final isEditing = itemToEdit != null;
    final codeCtrl = TextEditingController(text: itemToEdit?.itemCode ?? '');
    final nameCtrl = TextEditingController(text: itemToEdit?.itemName ?? '');
    String? selectedCategory = itemToEdit?.category;
    final descCtrl = TextEditingController(text: itemToEdit?.description ?? '');
    String? localError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final categories = _repo.getCategories();
          if (selectedCategory != null && !categories.contains(selectedCategory)) {
            selectedCategory = categories.isNotEmpty ? categories.first : null;
          }

          return AlertDialog(
            backgroundColor: AppColors.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: const BorderSide(color: AppColors.primary, width: 2.0),
            ),
            title: Text(
              isEditing ? 'EDIT ITEM MASTER' : 'ADD NEW ITEM MASTER',
              style: AppTypography.headlineSm,
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 480,
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

                    // 1. Bearing Item Code (Pill input, No heading, Clear placeholder)
                    TextField(
                      controller: codeCtrl,
                      readOnly: isEditing,
                      style: AppTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Bearing Item Code (e.g. PBI-6309-2RS) *',
                        hintStyle: AppTypography.bodySm.copyWith(color: AppColors.primary.withValues(alpha: 0.55)),
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
                        hintStyle: AppTypography.bodySm.copyWith(color: AppColors.primary.withValues(alpha: 0.55)),
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

                    // 3. Dynamic Category Dropdown (Pill dropdown, No heading, Dynamic options)
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      isExpanded: true,
                      decoration: InputDecoration(
                        hintText: 'Select Bearing Category *',
                        hintStyle: AppTypography.bodySm.copyWith(color: AppColors.primary.withValues(alpha: 0.55)),
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

                    // 4. Technical Specifications (Pill input, No heading, Clear placeholder)
                    TextField(
                      controller: descCtrl,
                      style: AppTypography.bodyMd,
                      decoration: InputDecoration(
                        hintText: 'Technical Dimensions & Specifications (Optional)',
                        hintStyle: AppTypography.bodySm.copyWith(color: AppColors.primary.withValues(alpha: 0.55)),
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
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL', style: TextStyle(color: AppColors.primary)),
              ),
              IndustrialButton(
                label: isEditing ? 'UPDATE ITEM' : 'SAVE ITEM',
                variant: IndustrialButtonVariant.primary,
                width: 140,
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
                  final warranty = itemToEdit?.defaultWarrantyMonths ?? 6;

                  final item = BearingItemModel(
                    itemCode: code,
                    itemName: name,
                    category: selectedCategory!,
                    defaultWarrantyMonths: warranty,
                    description: descCtrl.text.trim(),
                    createdAt: itemToEdit?.createdAt ?? DateTime.now(),
                  );

                  if (isEditing) {
                    _repo.updateItem(item);
                  } else {
                    _repo.addItem(item);
                  }
                  Navigator.pop(ctx);
                  setState(() {});
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDelete(String itemCode) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: AppColors.primary, width: 2.0),
        ),
        title: Text('DELETE ITEM $itemCode', style: AppTypography.headlineSm),
        content: Text(
          'Are you sure you want to remove item "$itemCode" from the Item Master catalog?',
          style: AppTypography.bodySm,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: AppColors.primary)),
          ),
          IndustrialButton(
            label: 'DELETE',
            variant: IndustrialButtonVariant.primary,
            width: 110,
            onPressed: () {
              _repo.deleteItem(itemCode);
              Navigator.pop(ctx);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paginated = _repo.getPaginatedMasterItems(
      page: _currentPage,
      pageSize: _pageSize,
      query: _searchQuery,
    );

    final startItem = paginated.totalCount == 0 ? 0 : (_currentPage - 1) * _pageSize + 1;
    final endItem = (_currentPage * _pageSize).clamp(0, paginated.totalCount);

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
              // Responsive Header with Category Master & Add Item
              AdminViewHeader(
                title: 'Bearing Item Master',
            actions: [
              IndustrialButton(
                label: 'CATEGORY MASTER',
                icon: Icons.category_outlined,
                variant: IndustrialButtonVariant.secondary,
                width: 180,
                onPressed: _showCategoryMasterDialog,
              ),
              const SizedBox(width: 8),
              IndustrialButton(
                label: 'ADD NEW ITEM',
                icon: Icons.add_circle_outline,
                variant: IndustrialButtonVariant.primary,
                width: 160,
                onPressed: () => _showAddOrEditDialog(),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spaceLg),

          // Search and Metric Bar
          IndustrialCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: AppTypography.bodyMd,
                    decoration: InputDecoration(
                      hintText: 'Search by item code, description, category...',
                      hintStyle: AppTypography.caption,
                      prefixIcon: const Icon(Icons.search, color: AppColors.primary, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18, color: AppColors.primary),
                              onPressed: () => _searchCtrl.clear(),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppDimensions.spaceMd),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                  ),
                  child: Text(
                    'TOTAL ITEMS: ${paginated.totalCount}',
                    style: const TextStyle(
                      color: AppColors.background,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spaceMd),

          // Items Table / List
          // Items Table / List
          IndustrialCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    const minTableWidth = 720.0;
                    final isNarrow = constraints.maxWidth < minTableWidth;

                    final tableWidget = SizedBox(
                      width: isNarrow ? minTableWidth : constraints.maxWidth,
                      child: Column(
                        children: [
                          // Table Column Header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(AppDimensions.radiusDefault),
                                topRight: Radius.circular(AppDimensions.radiusDefault),
                              ),
                            ),
                            child: const Row(
                              children: [
                                SizedBox(width: 50, child: Text('#', style: TextStyle(color: AppColors.background, fontWeight: FontWeight.bold, fontSize: 12))),
                                Expanded(flex: 3, child: Text('ITEM / BEARING CODE', style: TextStyle(color: AppColors.background, fontWeight: FontWeight.bold, fontSize: 12))),
                                Expanded(flex: 4, child: Text('PRODUCT DESCRIPTION', style: TextStyle(color: AppColors.background, fontWeight: FontWeight.bold, fontSize: 12))),
                                Expanded(flex: 2, child: Text('CATEGORY', style: TextStyle(color: AppColors.background, fontWeight: FontWeight.bold, fontSize: 12))),
                                Expanded(flex: 2, child: Text('DEFAULT WARRANTY', style: TextStyle(color: AppColors.background, fontWeight: FontWeight.bold, fontSize: 12))),
                                SizedBox(width: 90, child: Text('ACTIONS', textAlign: TextAlign.right, style: TextStyle(color: AppColors.background, fontWeight: FontWeight.bold, fontSize: 12))),
                              ],
                            ),
                          ),

                          // Table Rows
                          if (paginated.items.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Center(
                                child: Column(
                                  children: [
                                    const Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.primary),
                                    const SizedBox(height: 8),
                                    Text(
                                      _searchQuery.isEmpty
                                          ? 'No bearing items registered yet. Click "ADD NEW ITEM" above to create your catalog.'
                                          : 'No items found matching "$_searchQuery"',
                                      style: AppTypography.labelMd,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: paginated.items.length,
                              separatorBuilder: (context, index) => const Divider(color: AppColors.primary, height: 1, thickness: 0.5),
                              itemBuilder: (context, idx) {
                                final item = paginated.items[idx];
                                final rowNumber = (_currentPage - 1) * _pageSize + idx + 1;

                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 50,
                                        child: Text(
                                          rowNumber.toString().padLeft(2, '0'),
                                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Row(
                                          children: [
                                            const Icon(Icons.precision_manufacturing, size: 16, color: AppColors.primary),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                item.itemCode,
                                                style: AppTypography.mono.copyWith(fontWeight: FontWeight.bold),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 4,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.itemName,
                                              style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600, height: 1.2),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (item.description.isNotEmpty)
                                              Text(
                                                item.description,
                                                style: AppTypography.caption.copyWith(fontSize: 10, height: 1.2),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Container(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              border: Border.all(color: AppColors.primary, width: 1.0),
                                              borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                                            ),
                                            child: Text(
                                              item.category.toUpperCase(),
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          item.defaultWarrantyMonths == 0
                                              ? '0 Months (No Warranty)'
                                              : '${item.defaultWarrantyMonths} Months',
                                          style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 90,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            InkWell(
                                              onTap: () => _showAddOrEditDialog(itemToEdit: item),
                                              borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                                              child: const Padding(
                                                padding: EdgeInsets.all(6.0),
                                                child: Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            InkWell(
                                              onTap: () => _confirmDelete(item.itemCode),
                                              borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                                              child: const Padding(
                                                padding: EdgeInsets.all(6.0),
                                                child: Icon(Icons.delete_outline, size: 18, color: AppColors.primary),
                                              ),
                                            ),
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

                    if (isNarrow) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: tableWidget,
                      );
                    }
                    return tableWidget;
                  },
                ),

                // Table Pagination Footer (20 items per page)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.primary, width: 1.0)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 460;
                      return Flex(
                        direction: isMobile ? Axis.vertical : Axis.horizontal,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                        children: [
                          Text(
                            paginated.totalCount == 0
                                ? 'No records'
                                : 'Showing $startItem–$endItem of ${paginated.totalCount} items (Page $_currentPage of ${paginated.totalPages})',
                            style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isMobile) const SizedBox(height: 10),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OutlinedButton.icon(
                                onPressed: paginated.hasPrevious
                                    ? () => setState(() => _currentPage--)
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  minimumSize: const Size(0, 36),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  side: const BorderSide(color: AppColors.primary),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimensions.radiusMicro)),
                                ),
                                icon: const Icon(Icons.arrow_back, size: 14),
                                label: const Text('PREVIOUS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: paginated.hasNext
                                    ? () => setState(() => _currentPage++)
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  minimumSize: const Size(0, 36),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  side: const BorderSide(color: AppColors.primary),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimensions.radiusMicro)),
                                ),
                                icon: const Icon(Icons.arrow_forward, size: 14),
                                label: const Text('NEXT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
      },
    );
  }
}
