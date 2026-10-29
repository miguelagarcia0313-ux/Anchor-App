import 'dart:convert';

import 'package:anchor_app/modules/health/health_module.dart';
import 'package:anchor_app/modules/tasks/tasks_module.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The revamped Health screen is taller than the phone viewport, so scroll a
/// control into view before tapping it.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void _usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('health data persists per account', () async {
    SharedPreferences.setMockInitialValues({});
    final firstSession = HealthModule(userId: 'account-a');
    await firstSession.ready;
    await firstSession.addWeight(72, 'kg');
    await firstSession.setWaterGoal(88);
    await firstSession.addWater(16);
    await firstSession.addMedicine(
      name: 'Vitamin D',
      firstDoseHour: 8,
      firstDoseMinute: 15,
      intervalHours: 12,
    );
    await firstSession.setWeightUnit('kg');
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayKey =
        '${yesterday.year.toString().padLeft(4, '0')}-'
        '${yesterday.month.toString().padLeft(2, '0')}-'
        '${yesterday.day.toString().padLeft(2, '0')}';
    expect(firstSession.waterHistory.values, contains(16));

    final returningSession = HealthModule(userId: 'account-a');
    await returningSession.ready;
    expect(returningSession.weights, hasLength(1));
    expect(returningSession.waterGoalOz, 88);
    expect(returningSession.waterTodayOz, 16);
    expect(returningSession.medicines, hasLength(1));
    expect(returningSession.weightUnit, 'kg');
    expect(returningSession.medicines.single.intervalHours, 12);
    expect(returningSession.medicines.single.firstDoseMinute, 15);
    expect(returningSession.waterHistory.values, contains(16));
    expect(returningSession.waterHistory.containsKey(yesterdayKey), isFalse);

    final otherAccount = HealthModule(userId: 'account-b');
    await otherAccount.ready;
    expect(otherAccount.weights, isEmpty);
    expect(otherAccount.waterGoalOz, 64);
    expect(otherAccount.waterTodayOz, 0);
    expect(otherAccount.medicines, isEmpty);
    expect(otherAccount.weightUnit, 'lb');
    expect(otherAccount.waterHistory.values, isEmpty);
  });

  test('water history retains previous dates', () async {
    SharedPreferences.setMockInitialValues({});
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayKey =
        '${yesterday.year.toString().padLeft(4, '0')}-'
        '${yesterday.month.toString().padLeft(2, '0')}-'
        '${yesterday.day.toString().padLeft(2, '0')}';
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'health.water.daily',
      jsonEncode({'date': yesterdayKey, 'ounces': 12}),
    );
    await preferences.setString(
      'health.history-user.water.history',
      jsonEncode({yesterdayKey: 12}),
    );

    final module = HealthModule(userId: 'history-user');
    await module.ready;
    await module.addWater(8);

    expect(module.waterHistory[yesterdayKey], 12);
    expect(module.waterTodayOz, 8);
  });

  test('entries created back to back get unique ids', () async {
    SharedPreferences.setMockInitialValues({});
    final module = HealthModule(userId: 'unique-id-user');
    await module.ready;
    await module.addWeight(150, 'lb');
    await module.addWeight(151, 'lb');
    await module.addMedicine(
      name: 'Vitamin D',
      firstDoseHour: 8,
      firstDoseMinute: 0,
      intervalHours: 24,
    );
    await module.addMedicine(
      name: 'Zinc',
      firstDoseHour: 9,
      firstDoseMinute: 0,
      intervalHours: 24,
    );

    expect(module.weights.map((entry) => entry.id).toSet(), hasLength(2));
    expect(module.medicines.map((entry) => entry.id).toSet(), hasLength(2));
  });

  testWidgets('medication schedules create linked Tasks dose reminders', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final tasks = TasksModule(userId: 'medication-link-user');
    final health = HealthModule(
      userId: 'medication-link-user',
      onMedicineSaved: (medicine) => tasks.syncMedicationDoseReminders(
        medicationId: medicine.id,
        medicationName: medicine.name,
        firstDoseHour: medicine.firstDoseHour,
        firstDoseMinute: medicine.firstDoseMinute,
        intervalHours: medicine.intervalHours,
      ),
      onMedicineDeleted: tasks.removeMedicationDoseReminders,
    );
    await health.ready;
    await health.addMedicine(
      name: 'Vitamin D',
      firstDoseHour: 0,
      firstDoseMinute: 0,
      intervalHours: 8,
    );
    await tasks.ready;

    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: tasks.buildDetailView)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Take Vitamin D - Dose 1'), findsOneWidget);
    expect(find.textContaining('Medication: Vitamin D'), findsWidgets);
    expect(
      tester.widgetList<Checkbox>(find.byType(Checkbox)).length,
      greaterThanOrEqualTo(3),
    );

    await health.deleteMedicine(health.medicines.single);
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: tasks.buildDetailView)),
    );
    await tester.pumpAndSettle();
    expect(find.text('No tasks or reminders yet!'), findsOneWidget);
  });

  testWidgets('health tracks weight, water, and daily medicines', (
    tester,
  ) async {
    _usePhoneScreen(tester);
    SharedPreferences.setMockInitialValues({});
    final tasks = TasksModule(userId: 'health-test-user');
    final module = HealthModule(
      userId: 'health-test-user',
      onMedicineSaved: (medicine) => tasks.syncMedicationDoseReminders(
        medicationId: medicine.id,
        medicationName: medicine.name,
        firstDoseHour: medicine.firstDoseHour,
        firstDoseMinute: medicine.firstDoseMinute,
        intervalHours: medicine.intervalHours,
      ),
      onMedicineDeleted: tasks.removeMedicationDoseReminders,
    );
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: module.buildDetailView)),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byTooltip('Add weight'));
    await tester.enterText(find.byType(TextField).first, '150');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // With a single entry the Latest and Average tiles both read 150 lb.
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

    // The unit is now a lb/kg segmented toggle instead of a dropdown.
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<String>),
        matching: find.text('kg'),
      ),
    );
    await tester.pumpAndSettle();
    expect(module.weightUnit, 'kg');
    final kilogramChart = tester.widget<LineChart>(find.byType(LineChart));
    expect(kilogramChart.data.minY, closeTo(40, 0.0001));
    expect(kilogramChart.data.maxY, closeTo(100, 0.0001));

    await _tapVisible(tester, find.byTooltip('Set water goal'));
    await tester.enterText(find.byType(TextField).first, '80');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byTooltip('Add water'));
    await tester.enterText(find.byType(TextField).first, '8');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('8 / 80 fl oz'), findsOneWidget);

    await _tapVisible(tester, find.byTooltip('Remove water'));
    await tester.enterText(find.byType(TextField).first, '8');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('0 / 80 fl oz'), findsOneWidget);

    await _tapVisible(tester, find.byTooltip('Add medication or supplement'));
    await tester.enterText(find.byType(TextField).first, 'Vitamin D');
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every 12 hours').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Vitamin D'), findsOneWidget);
    expect(module.medicines.single.firstDoseHour, 8);
    expect(module.medicines.single.firstDoseMinute, 0);
    expect(module.medicines.single.intervalHours, 12);

    await _tapVisible(tester, find.byType(Checkbox).first);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    await tasks.ready;
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: tasks.buildDetailView)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Take Vitamin D - Dose 1'), findsOneWidget);
    expect(find.text('Take Vitamin D - Dose 2'), findsOneWidget);
    expect(
      find.textContaining('Medication: Vitamin D'),
      findsAtLeastNWidgets(2),
    );

    await module.deleteMedicine(module.medicines.single);
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: tasks.buildDetailView)),
    );
    await tester.pumpAndSettle();
    expect(find.text('No tasks or reminders yet!'), findsOneWidget);
  });

  testWidgets('summary card shows live health numbers', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final module = HealthModule(userId: 'summary-user');
    await module.ready;
    await module.addWater(16);
    await module.addWeight(150, 'lb');
    await module.addMedicine(
      name: 'Vitamin D',
      firstDoseHour: 8,
      firstDoseMinute: 0,
      intervalHours: 24,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: module.buildSummaryCard)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('16/64 fl oz water · 150 lb · 0/1 meds taken'),
      findsOneWidget,
    );

    await module.toggleMedicine(module.medicines.single, true);
    await tester.pumpAndSettle();
    expect(
      find.text('16/64 fl oz water · 150 lb · 1/1 meds taken'),
      findsOneWidget,
    );
  });

  testWidgets('quick-add chips fill the water goal and start a streak', (
    tester,
  ) async {
    _usePhoneScreen(tester);
    SharedPreferences.setMockInitialValues({});
    final module = HealthModule(userId: 'quick-water-user');
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: module.buildDetailView)),
    );
    await tester.pumpAndSettle();

    expect(find.text('0 / 64 fl oz'), findsOneWidget);
    expect(find.text('Hit your goal to start a streak'), findsOneWidget);

    await _tapVisible(tester, find.text('+24 oz'));
    await _tapVisible(tester, find.text('+24 oz'));
    expect(find.text('48 / 64 fl oz'), findsOneWidget);
    expect(find.text('16 fl oz to go'), findsOneWidget);

    await _tapVisible(tester, find.text('+16 oz'));
    expect(find.text('64 / 64 fl oz'), findsOneWidget);
    expect(find.text('Goal reached!'), findsOneWidget);
    expect(find.text('1 day streak'), findsOneWidget);
    expect(module.waterTodayOz, 64);
  });

  testWidgets('weight range selector filters the chart and stats', (
    tester,
  ) async {
    _usePhoneScreen(tester);
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'health.range-user.weights': [
        jsonEncode({
          'id': 'old',
          'kilograms': 80.0,
          'recordedAt': now.subtract(const Duration(days: 100)).toIso8601String(),
        }),
        jsonEncode({
          'id': 'new',
          'kilograms': 75.0,
          'recordedAt': now.toIso8601String(),
        }),
      ],
    });
    final module = HealthModule(userId: 'range-user');
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: module.buildDetailView)),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 entries'), findsOneWidget);
    expect(find.text('-11 lb'), findsOneWidget);
    expect(
      tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .lineBarsData
          .single
          .spots,
      hasLength(2),
    );

    await tester.tap(find.text('7D'));
    await tester.pumpAndSettle();
    expect(find.text('1 entry'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(
      tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .lineBarsData
          .single
          .spots,
      hasLength(1),
    );
  });

  testWidgets('removing a medicine asks for confirmation first', (
    tester,
  ) async {
    _usePhoneScreen(tester);
    SharedPreferences.setMockInitialValues({});
    final module = HealthModule(userId: 'remove-medicine-user');
    await module.ready;
    await module.addMedicine(
      name: 'Vitamin D',
      firstDoseHour: 8,
      firstDoseMinute: 0,
      intervalHours: 24,
    );
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: module.buildDetailView)),
    );
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byTooltip('Remove item'));
    expect(find.text('Remove Vitamin D?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(module.medicines, hasLength(1));
    expect(find.text('Vitamin D'), findsOneWidget);

    await _tapVisible(tester, find.byTooltip('Remove item'));
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(module.medicines, isEmpty);
    expect(find.text('Vitamin D'), findsNothing);
  });
}