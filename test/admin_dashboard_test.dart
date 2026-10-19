import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pivot_bearings_app/features/admin_dashboard/presentation/screens/admin_dashboard_screen.dart';

Future<void> pumpScreen(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('AdminDashboardScreen desktop layout test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: AdminDashboardScreen(),
      ),
    );
    await pumpScreen(tester);

    expect(find.text('PIVOT BEARINGS'), findsOneWidget);
    expect(find.text('DASHBOARD'), findsWidgets);
  });

  testWidgets('AdminDashboardScreen tab switching test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: AdminDashboardScreen(),
      ),
    );
    await pumpScreen(tester);

    final tabsToTest = [
      'Role Assignment',
      'QR Generation',
      'Item Master',
      'QR Registry',
      'Customer Accounts',
      'Bearing Lifecycle',
      'Verification Proofs',
      'Company Settings',
    ];

    for (final tab in tabsToTest) {
      final tabFinder = find.widgetWithText(InkWell, tab).first;
      expect(tabFinder, findsOneWidget);
      await tester.tap(tabFinder);
      await pumpScreen(tester);
    }
  });

  testWidgets('AdminDashboardScreen mobile layout and drawer test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: AdminDashboardScreen(),
      ),
    );
    await pumpScreen(tester);

    final menuFinder = find.byIcon(Icons.menu);
    expect(menuFinder, findsOneWidget);

    // Open drawer
    await tester.tap(menuFinder);
    await pumpScreen(tester);

    expect(find.text('PIVOT BEARINGS INDIA'), findsOneWidget);
    expect(find.text('OPERATOR VIEW'), findsOneWidget);
  });

  testWidgets('Item Master displays bearings and QR Generation selects items', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: AdminDashboardScreen(),
      ),
    );
    await pumpScreen(tester);

    // 1. Navigate to Item Master
    final itemMasterTab = find.widgetWithText(InkWell, 'Item Master').first;
    await tester.tap(itemMasterTab);
    await pumpScreen(tester);

    expect(find.text('Bearing Item Master'), findsOneWidget);
    expect(find.text('PBI-6204-ZZ'), findsOneWidget);
    expect(find.text('PBI-6205-2RS'), findsOneWidget);

    // 2. Navigate to QR Generation
    final qrGenTab = find.widgetWithText(InkWell, 'QR Generation').first;
    await tester.tap(qrGenTab);
    await pumpScreen(tester);

    expect(find.text('QR Bulk Generation'), findsOneWidget);
    // Should display placeholder without default item selection
    expect(find.text('Select Bearing/item'), findsOneWidget);

    // 3. Tap to open item selector dialog
    final selectFinder = find.text('SELECT');
    expect(selectFinder, findsOneWidget);
    await tester.tap(selectFinder);
    await pumpScreen(tester);

    // Verify dialog opened with bearing items
    expect(find.text('SELECT BEARING / ITEM CODE'), findsOneWidget);
    expect(find.text('PBI-6309-2RS'), findsOneWidget);

    // Tap to select PBI-6309-2RS
    final targetItem = find.text('PBI-6309-2RS');
    await tester.tap(targetItem);
    await pumpScreen(tester);

    // Verify QR Bulk Generation now shows PBI-6309-2RS selected
    expect(find.text('PBI-6309-2RS'), findsOneWidget);
  });
}
