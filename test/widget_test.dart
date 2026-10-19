import 'package:flutter_test/flutter_test.dart';
import 'package:pivot_bearings_app/main.dart';

void main() {
  testWidgets('PivotBearingsApp foundation smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PivotBearingsApp());
    await tester.pump();
    expect(find.byType(PivotBearingsApp), findsOneWidget);
  });
}
