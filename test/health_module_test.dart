import 'package:anchor_app/modules/health/health_module.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('health data persists per account', () async {
    SharedPreferences.setMockInitialValues({});
    final firstSession = HealthModule(userId: 'account-a');
    await firstSession.ready;
    await firstSession.addWeight(72, 'kg');
    await firstSession.setWaterGoal(88);
    await firstSession.addWater(16);
    await firstSession.addMedicine('Vitamin D');

    final returningSession = HealthModule(userId: 'account-a');
    await returningSession.ready;
    expect(returningSession.weights, hasLength(1));
    expect(returningSession.waterGoalOz, 88);
    expect(returningSession.waterTodayOz, 16);
    expect(returningSession.medicines, hasLength(1));

    final otherAccount = HealthModule(userId: 'account-b');
    await otherAccount.ready;
    expect(otherAccount.weights, isEmpty);
    expect(otherAccount.waterGoalOz, 64);
    expect(otherAccount.waterTodayOz, 0);
    expect(otherAccount.medicines, isEmpty);
  });

  testWidgets('health tracks weight, water, and daily medicines', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final module = HealthModule(userId: 'health-test-user');
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: module.buildDetailView)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add weight'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '150');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('150 lb'), findsNWidgets(2));

    await module.addWeight(40, 'kg');
    await module.addWeight(100, 'kg');
    await tester.pumpAndSettle();
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.minY, closeTo(40 * 2.2046226218, 0.0001));
    expect(chart.data.maxY, closeTo(100 * 2.2046226218, 0.0001));
    final plottedWeights = chart.data.lineBarsData.single.spots
        .map((spot) => spot.y)
        .toList();
    expect(plottedWeights, hasLength(3));
    expect(plottedWeights[0], closeTo(150, 0.0001));
    expect(plottedWeights[1], closeTo(40 * 2.2046226218, 0.0001));
    expect(plottedWeights[2], closeTo(100 * 2.2046226218, 0.0001));

    await tester.tap(find.byTooltip('Set water goal'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '80');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add water'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '8');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('8 / 80 fl oz'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove water'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '8');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('0 / 80 fl oz'), findsOneWidget);

    final addMedicineButton = find.byTooltip('Add medication or supplement');
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(addMedicineButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Vitamin D');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Vitamin D'), findsOneWidget);

    await tester.ensureVisible(find.byType(Checkbox).first);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });
}
