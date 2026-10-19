import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/supabase_service.dart';
import '../models/bearing_item_model.dart';

class PaginatedResult<T> {
  final List<T> items;
  final int totalCount;
  final int currentPage;
  final int pageSize;
  final int totalPages;

  const PaginatedResult({
    required this.items,
    required this.totalCount,
    required this.currentPage,
    required this.pageSize,
    required this.totalPages,
  });

  bool get hasNext => currentPage < totalPages;
  bool get hasPrevious => currentPage > 1;
}

/// Persistent catalog repository for Bearing Item Master
/// Connects to browser/device SharedPreferences & Supabase `bearing_items`
class ItemMasterRepository {
  static final ItemMasterRepository _instance = ItemMasterRepository._internal();
  factory ItemMasterRepository() => _instance;

  static const String _storageKey = 'pbi_bearing_catalog_v1';
  static const String _categoriesStorageKey = 'pbi_bearing_categories_v1';
  final List<BearingItemModel> _items = [];
  final List<String> _categories = [];

  ItemMasterRepository._internal() {
    _items.addAll(_defaultBearingCatalog);
    _categories.addAll(_defaultCategories);
    _initStorage();
  }

  Future<void> _initStorage() async {
    await loadFromLocalStorage();
    await loadCategoriesFromLocalStorage();
    await fetchItemsFromSupabase();
    await fetchCategoriesFromSupabase();
  }

  /// Loads locally saved catalog items from browser/device storage
  Future<void> loadFromLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonString);
        final loaded = decoded
            .map((m) => BearingItemModel.fromJson(Map<String, dynamic>.from(m)))
            .toList();
        if (loaded.isNotEmpty) {
          _items.clear();
          _items.addAll(loaded);
          return;
        }
      }
    } catch (_) {}

    // First run fallback: seed default catalog into persistent storage
    _saveToLocalStorage();
  }

  /// Persists current catalog to browser/device storage
  Future<void> _saveToLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(_items.map((it) => it.toJson()).toList());
      await prefs.setString(_storageKey, jsonString);
    } catch (_) {}
  }

  /// Initial production catalog
  static List<BearingItemModel> get _defaultBearingCatalog => [
    BearingItemModel(
      itemCode: 'PBI-6204-ZZ',
      itemName: 'Deep Groove Ball Bearing 6204 (Dual Metal Shielded)',
      category: 'Ball Bearing',
      defaultWarrantyMonths: 6,
      description: '20mm bore x 47mm OD x 14mm width. High speed, standard industrial electric motors.',
      createdAt: DateTime(2026, 1, 1),
    ),
    BearingItemModel(
      itemCode: 'PBI-6205-2RS',
      itemName: 'Deep Groove Ball Bearing 6205 (Dual Rubber Sealed)',
      category: 'Ball Bearing',
      defaultWarrantyMonths: 6,
      description: '25mm bore x 52mm OD x 15mm width. Contaminant-resistant, conveyor and pump duty.',
      createdAt: DateTime(2026, 1, 1),
    ),
    BearingItemModel(
      itemCode: 'PBI-6309-2RS',
      itemName: 'Heavy Duty Deep Groove Ball Bearing 6309',
      category: 'Ball Bearing',
      defaultWarrantyMonths: 12,
      description: '45mm bore x 100mm OD x 25mm width. High dynamic load capacity for heavy industrial gearboxes.',
      createdAt: DateTime(2026, 1, 1),
    ),
    BearingItemModel(
      itemCode: 'PBI-22216-E',
      itemName: 'Spherical Roller Bearing 22216 (Self-Aligning)',
      category: 'Roller Bearing',
      defaultWarrantyMonths: 18,
      description: '80mm bore x 140mm OD x 33mm width. Heavy industrial vibration, mining, and shaft deflection duty.',
      createdAt: DateTime(2026, 1, 1),
    ),
    BearingItemModel(
      itemCode: 'PBI-30206-CR',
      itemName: 'Single Row Tapered Roller Bearing 30206',
      category: 'Tapered Roller',
      defaultWarrantyMonths: 12,
      description: '30mm bore x 62mm OD x 17.25mm width. Combined heavy radial and axial thrust loads.',
      createdAt: DateTime(2026, 1, 1),
    ),
    BearingItemModel(
      itemCode: 'PBI-NU208-ECP',
      itemName: 'Cylindrical Roller Bearing NU208',
      category: 'Cylindrical Roller',
      defaultWarrantyMonths: 12,
      description: '40mm bore x 80mm OD x 18mm width. High radial load capacity, reinforced polyamide cage.',
      createdAt: DateTime(2026, 1, 1),
    ),
    BearingItemModel(
      itemCode: 'PBI-7208-BECBP',
      itemName: 'Angular Contact Ball Bearing 7208 (40° Angle)',
      category: 'Angular Contact',
      defaultWarrantyMonths: 12,
      description: '40mm bore x 80mm OD x 18mm width. High precision spindle drives and centrifugal pumps.',
      createdAt: DateTime(2026, 1, 1),
    ),
    BearingItemModel(
      itemCode: 'PBI-51105',
      itemName: 'Single Direction Thrust Ball Bearing 51105',
      category: 'Thrust Bearing',
      defaultWarrantyMonths: 6,
      description: '25mm bore x 42mm OD x 11mm width. Pure axial load support for vertical jacks and crane hooks.',
      createdAt: DateTime(2026, 1, 1),
    ),
  ];

  /// Asynchronously fetches from Supabase table `bearing_items` and merges with local storage
  Future<List<BearingItemModel>> fetchItemsFromSupabase() async {
    if (SupabaseService.isInitialized) {
      try {
        final res = await SupabaseService.client
            .from('bearing_items')
            .select()
            .order('item_code', ascending: true);

        if (res.isNotEmpty) {
          final loaded = res.map((m) => BearingItemModel.fromJson(m)).toList();
          final Map<String, BearingItemModel> mergedMap = {
            for (final it in loaded) it.itemCode: it,
          };
          for (final local in _items) {
            mergedMap.putIfAbsent(local.itemCode, () => local);
          }
          _items.clear();
          _items.addAll(mergedMap.values);
          await _saveToLocalStorage();
          return List.unmodifiable(_items);
        }
      } catch (_) {
        // Table may not yet be migrated or offline; gracefully use local storage catalog
      }
    }
    return List.unmodifiable(_items);
  }

  List<BearingItemModel> getAllItems() {
    if (_items.isEmpty) {
      _items.addAll(_defaultBearingCatalog);
    }
    return List.unmodifiable(_items);
  }

  BearingItemModel? findByCode(String code) {
    final clean = code.trim().toUpperCase();
    try {
      return _items.firstWhere((it) => it.itemCode == clean);
    } catch (_) {
      return null;
    }
  }

  /// Paginated query for Item Master screen (default 20 items per page)
  PaginatedResult<BearingItemModel> getPaginatedMasterItems({
    int page = 1,
    int pageSize = 20,
    String query = '',
  }) {
    return _queryItems(page: page, pageSize: pageSize, query: query);
  }

  /// Paginated query for dropdown / modal selector in QR Bulk Generation (10 items per page)
  PaginatedResult<BearingItemModel> getDropdownItems({
    int page = 1,
    int pageSize = 10,
    String query = '',
  }) {
    return _queryItems(page: page, pageSize: pageSize, query: query);
  }

  PaginatedResult<BearingItemModel> _queryItems({
    required int page,
    required int pageSize,
    required String query,
  }) {
    if (_items.isEmpty) {
      _items.addAll(_defaultBearingCatalog);
    }

    final cleanQuery = query.trim().toUpperCase();
    List<BearingItemModel> filtered = _items;

    if (cleanQuery.isNotEmpty) {
      filtered = _items.where((it) {
        return it.itemCode.toUpperCase().contains(cleanQuery) ||
            it.itemName.toUpperCase().contains(cleanQuery) ||
            it.category.toUpperCase().contains(cleanQuery) ||
            it.description.toUpperCase().contains(cleanQuery);
      }).toList();
    }

    final totalCount = filtered.length;
    final totalPages = (totalCount / pageSize).ceil().clamp(1, 9999);
    final clampedPage = page.clamp(1, totalPages);

    final startIndex = (clampedPage - 1) * pageSize;
    final endIndex = (startIndex + pageSize).clamp(0, totalCount);

    final pageItems = startIndex < totalCount
        ? filtered.sublist(startIndex, endIndex)
        : <BearingItemModel>[];

    return PaginatedResult<BearingItemModel>(
      items: pageItems,
      totalCount: totalCount,
      currentPage: clampedPage,
      pageSize: pageSize,
      totalPages: totalPages,
    );
  }

  bool addItem(BearingItemModel item) {
    final cleanCode = item.itemCode.trim().toUpperCase();
    if (cleanCode.isEmpty) return false;

    final existingIndex = _items.indexWhere((it) => it.itemCode == cleanCode);
    if (existingIndex >= 0) {
      _items[existingIndex] = item;
    } else {
      _items.insert(0, item);
    }

    _saveToLocalStorage();

    // Async push to Supabase in background
    if (SupabaseService.isInitialized) {
      SupabaseService.client.from('bearing_items').upsert(item.toJson()).catchError((_) {});
    }

    return true;
  }

  bool updateItem(BearingItemModel item) {
    final cleanCode = item.itemCode.trim().toUpperCase();
    final index = _items.indexWhere((it) => it.itemCode == cleanCode);
    if (index >= 0) {
      _items[index] = item;
      _saveToLocalStorage();
      if (SupabaseService.isInitialized) {
        SupabaseService.client.from('bearing_items').update(item.toJson()).eq('item_code', cleanCode).catchError((_) {});
      }
      return true;
    }
    return false;
  }

  bool deleteItem(String itemCode) {
    final cleanCode = itemCode.trim().toUpperCase();
    final initialLength = _items.length;
    _items.removeWhere((it) => it.itemCode == cleanCode);

    if (_items.length < initialLength) {
      _saveToLocalStorage();
      if (SupabaseService.isInitialized) {
        SupabaseService.client.from('bearing_items').delete().eq('item_code', cleanCode).catchError((_) {});
      }
      return true;
    }

    return false;
  }

  static List<String> get _defaultCategories => [
    'Ball Bearing',
    'Roller Bearing',
    'Tapered Roller',
    'Cylindrical Roller',
    'Angular Contact',
    'Thrust Bearing',
    'Spherical Roller',
    'Needle Roller',
  ];

  List<String> getCategories() {
    if (_categories.isEmpty) {
      _categories.addAll(_defaultCategories);
    }
    for (final it in _items) {
      if (it.category.isNotEmpty && !_categories.contains(it.category)) {
        _categories.add(it.category);
      }
    }
    return List.unmodifiable(_categories);
  }

  Future<void> addCategory(String category) async {
    final clean = category.trim();
    if (clean.isEmpty) return;
    if (!_categories.contains(clean)) {
      _categories.add(clean);
      await saveCategoriesToLocalStorage();
      if (SupabaseService.isInitialized) {
        try {
          await SupabaseService.client.from('bearing_categories').insert({
            'name': clean,
          });
        } catch (_) {}
      }
    }
  }

  Future<void> deleteCategory(String category) async {
    _categories.remove(category);
    await saveCategoriesToLocalStorage();
    if (SupabaseService.isInitialized) {
      try {
        await SupabaseService.client.from('bearing_categories').delete().eq('name', category);
      } catch (_) {}
    }
  }

  Future<void> loadCategoriesFromLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_categoriesStorageKey);
      if (list != null && list.isNotEmpty) {
        _categories.clear();
        _categories.addAll(list);
        return;
      }
    } catch (_) {}
    _categories.clear();
    _categories.addAll(_defaultCategories);
    await saveCategoriesToLocalStorage();
  }

  Future<void> saveCategoriesToLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_categoriesStorageKey, _categories);
    } catch (_) {}
  }

  Future<List<String>> fetchCategoriesFromSupabase() async {
    if (SupabaseService.isInitialized) {
      try {
        final res = await SupabaseService.client
            .from('bearing_categories')
            .select('name')
            .order('name', ascending: true);
        if (res.isNotEmpty) {
          for (final row in res) {
            final name = row['name']?.toString();
            if (name != null && name.isNotEmpty && !_categories.contains(name)) {
              _categories.add(name);
            }
          }
          await saveCategoriesToLocalStorage();
        }
      } catch (_) {}
    }
    return getCategories();
  }
}
