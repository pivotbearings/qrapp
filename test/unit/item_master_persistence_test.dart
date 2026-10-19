import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pivot_bearings_app/features/item_master/data/models/bearing_item_model.dart';
import 'package:pivot_bearings_app/features/item_master/data/repositories/item_master_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Item Master preserves user-created items across reloads & sessions', () async {
    final repo = ItemMasterRepository();
    await repo.loadFromLocalStorage();

    const customCode = 'PBI-CUSTOM-999';
    final customItem = BearingItemModel(
      itemCode: customCode,
      itemName: 'Custom High Precision Ceramic Bearing',
      category: 'Ceramic Bearing',
      defaultWarrantyMonths: 24,
      description: 'Special test ceramic unit',
      createdAt: DateTime.now(),
    );

    repo.addItem(customItem);

    // Verify item is added
    expect(repo.findByCode(customCode), isNotNull);
    expect(repo.findByCode(customCode)!.itemName, equals('Custom High Precision Ceramic Bearing'));

    // Simulate page reload: reload from local storage
    await repo.loadFromLocalStorage();

    // Verify item persists
    final foundAfterReload = repo.findByCode(customCode);
    expect(foundAfterReload, isNotNull, reason: 'Custom item must not vanish on refresh');
    expect(foundAfterReload!.defaultWarrantyMonths, equals(24));
  });
}
