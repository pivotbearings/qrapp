class BearingItemModel {
  final String itemCode;
  final String itemName;
  final String category;
  final int defaultWarrantyMonths;
  final String description;
  final DateTime createdAt;

  const BearingItemModel({
    required this.itemCode,
    required this.itemName,
    required this.category,
    this.defaultWarrantyMonths = 6,
    this.description = '',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'item_code': itemCode,
    'item_name': itemName,
    'category': category,
    'default_warranty_months': defaultWarrantyMonths,
    'description': description,
    'created_at': createdAt.toIso8601String(),
  };

  factory BearingItemModel.fromJson(Map<String, dynamic> map) => BearingItemModel(
    itemCode: (map['item_code'] ?? '').toString().toUpperCase().trim(),
    itemName: (map['item_name'] ?? '').toString().trim(),
    category: (map['category'] ?? 'Industrial Bearing').toString().trim(),
    defaultWarrantyMonths: map['default_warranty_months'] is int
        ? map['default_warranty_months']
        : int.tryParse(map['default_warranty_months']?.toString() ?? '6') ?? 6,
    description: (map['description'] ?? '').toString().trim(),
    createdAt: map['created_at'] != null
        ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
        : DateTime.now(),
  );

  BearingItemModel copyWith({
    String? itemCode,
    String? itemName,
    String? category,
    int? defaultWarrantyMonths,
    String? description,
    DateTime? createdAt,
  }) {
    return BearingItemModel(
      itemCode: itemCode ?? this.itemCode,
      itemName: itemName ?? this.itemName,
      category: category ?? this.category,
      defaultWarrantyMonths: defaultWarrantyMonths ?? this.defaultWarrantyMonths,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
