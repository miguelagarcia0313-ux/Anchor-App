import 'package:anchor_app/modules/fitness/fitness.dart';
import 'package:anchor_app/shared/module_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
void main() {
  test('category totals persist per account', () async {
    SharedPreferences.setMockInitialValues({});
    final firstSession = FitnessModule(userId: 'totals-account');
    await firstSession.ready;
    firstSession.updateCategoryDuration(
      'Core',
      const Duration(minutes: 2, seconds: 34),
    );
    await firstSession.persistCategoryDurations();

    final returningSession = FitnessModule(userId: 'totals-account');
    await returningSession.ready;
    expect(
      returningSession.categoryDurations['Core'],
      const Duration(minutes: 2, seconds: 34),
    );

    final otherAccount = FitnessModule(userId: 'other-totals-account');
    await otherAccount.ready;
    expect(otherAccount.categoryDurations, isEmpty);
  });

  test('workout and category ordering persists per account', () async {
    SharedPreferences.setMockInitialValues({});
    final module = FitnessModule(userId: 'reorder-account');
    await module.ready;
    await module.addEntry(
      const WorkoutDraft(
        name: 'Plank',
        category: 'Core',
        sets: 3,
        reps: 1,
        minimumWeight: 0,
      ),
    );
    await module.addEntry(
      const WorkoutDraft(
        name: 'Crunches',
        category: 'Core',
        sets: 3,
        reps: 12,
        minimumWeight: 0,
      ),
    );
    await module.addEntry(
      const WorkoutDraft(
        name: 'Squats',
        category: 'Legs',
        sets: 3,
        reps: 10,
        minimumWeight: 0,
      ),
    );

    await module.reorderWorkouts('Core', 0, 1);
    await module.reorderCategories(0, 1);

    final restoredModule = FitnessModule(userId: 'reorder-account');
    await restoredModule.ready;
    expect(restoredModule.categories, ['Legs', 'Core']);
    expect(
      restoredModule.entriesForCategory('Core').map((entry) => entry.name),
      ['Crunches', 'Plank'],
    );
  });

  testWidgets('drag handles reorder categories and workouts', (tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final module = FitnessModule(userId: 'drag-reorder-account');
  await module.ready;
  for (final workout in [
    (name: 'Plank', category: 'Core'),
    (name: 'Crunches', category: 'Core'),
    (name: 'Squats', category: 'Legs'),
  ]) {
    await module.addEntry(
      WorkoutDraft(
        name: workout.name,
        category: workout.category,
        sets: 3,
        reps: 10,
        minimumWeight: 0,
      ),
    );
  }
  await tester.pumpWidget(
    MaterialApp(home: Builder(builder: module.buildDetailView)),
  );
  await tester.pumpAndSettle();

  // Flutter only reorders once the dragged item's bottom edge is in the
  // lower half of the item it is passing, so measure instead of guessing.
  final coreCard = find.byKey(const ValueKey('category:Core'));
  final legsCard = find.byKey(const ValueKey('category:Legs'));
  final coreRect = tester.getRect(coreCard);
  final legsRect = tester.getRect(legsCard);
  expect(coreRect.height, greaterThan(legsRect.height));

  final coreDragHandle = find.descendant(
    of: coreCard,
    matching: find.byIcon(Icons.drag_handle),
  );
  await tester.drag(
    coreDragHandle.first,
    Offset(0, legsRect.bottom - coreRect.bottom - 4),
  );
  await tester.pumpAndSettle();
  expect(module.categories, ['Legs', 'Core']);

  final workoutPitch =
      tester.getTopLeft(find.text('Crunches')).dy -
      tester.getTopLeft(find.text('Plank')).dy;
  final workoutDragHandles = find.descendant(
    of: find.byKey(const ValueKey('category:Core')),
    matching: find.byIcon(Icons.drag_handle),
  );
  await tester.drag(workoutDragHandles.at(1), Offset(0, workoutPitch - 4));
  await tester.pumpAndSettle();
  expect(module.entriesForCategory('Core').map((entry) => entry.name), [
    'Crunches',
    'Plank',
  ]);
});

 testWidgets('guided workout runs sets, rests, and workout picking', (
  tester,
) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // Silence HapticFeedback calls so they don't throw in tests.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  // Let animations finish without pumpAndSettle (timers are running).
  Future<void> step() async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> realWait() => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 1100)),
  );

  Future<void> finishSet() async {
    await tester.tap(find.text('Finish set'));
    await step();
  }

  SharedPreferences.setMockInitialValues({});
  final module = FitnessModule(userId: 'guided-account');
  await module.ready;
  await module.addEntry(
    const WorkoutDraft(
      name: 'Pullups',
      category: 'Core',
      sets: 3,
      reps: 10,
      minimumWeight: 0,
    ),
  );
  await module.addEntry(
    const WorkoutDraft(
      name: 'Plank',
      category: 'Core',
      sets: 3,
      reps: 1,
      minimumWeight: 0,
    ),
  );

  await tester.pumpWidget(
    MaterialApp(home: Builder(builder: module.buildDetailView)),
  );
  await tester.pumpAndSettle();

  // Setup sheet -> start with defaults.
  await tester.tap(find.text('Start workout'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start'));
  await tester.pumpAndSettle();
  expect(find.text('Workout 1 of 2'), findsOneWidget);
  expect(find.text('Set 1 of 3'), findsOneWidget);

  // Start, let real time pass, pause, confirm the timer holds, resume.
  await tester.tap(find.text('Start'));
  await step();
  expect(find.text('Pause'), findsOneWidget);
  await realWait();
  await tester.pump(const Duration(seconds: 1));
  final currentTimer = find.descendant(
    of: find.byType(ModuleBottomSheet),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Text && RegExp(r'^0:[0-9]{2}$').hasMatch(widget.data ?? ''),
    ),
  );
  expect(tester.widget<Text>(currentTimer.first).data, isNot('0:00'));

  await tester.tap(find.text('Pause'));
  await step();
  expect(find.text('Resume'), findsOneWidget);
  final pausedTime = tester.widget<Text>(currentTimer.first).data;
  await realWait();
  await tester.pump(const Duration(seconds: 2));
  expect(tester.widget<Text>(currentTimer.first).data, pausedTime);

  await tester.tap(find.text('Resume'));
  await step();

  // Three sets, with a rest between each one.
  await finishSet();
  expect(find.text('Rest before set 2 of 3'), findsOneWidget);
  await tester.tap(find.text('Skip rest'));
  await step();
  await finishSet();
  expect(find.text('Rest before set 3 of 3'), findsOneWidget);
  await tester.tap(find.text('Skip rest'));
  await step();
  await finishSet();
  expect(find.text('Rest before your next workout'), findsOneWidget);

  // Close the sheet, come back, and continue where we left off.
  await tester.tap(find.byTooltip('Close workout session'));
  await step();
  await tester.tap(find.text('Start workout'));
  await step();
  expect(find.text('Continue'), findsOneWidget);
  expect(find.text('Reset'), findsOneWidget);
  await tester.tap(find.text('Continue'));
  await step();
  await step();
  expect(find.text('Rest before your next workout'), findsOneWidget);

  // Skip rest, pick the next workout.
  await tester.tap(find.text('Skip rest'));
  await step();
  expect(find.text('Choose your next workout'), findsOneWidget);
  await tester.tap(
    find.descendant(
      of: find.byType(ModuleBottomSheet),
      matching: find.text('Plank'),
    ),
  );
  await step();
  expect(find.text('Workout 2 of 2'), findsOneWidget);

  // Run Plank's three sets.
  await tester.tap(find.text('Start'));
  await step();
  await realWait();
  await tester.pump(const Duration(seconds: 1));
  await finishSet();
  await tester.tap(find.text('Skip rest'));
  await step();
  await finishSet();
  await tester.tap(find.text('Skip rest'));
  await step();
  await finishSet();

  expect(find.text('Workout complete'), findsOneWidget);
  final durationLabels = find.byWidgetPredicate(
    (widget) =>
        widget is Text && RegExp(r'^0:[0-9]{2}$').hasMatch(widget.data ?? ''),
  );
  expect(durationLabels, findsNWidgets(2));
  expect(find.text('0:00'), findsNothing);

  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();

  // Total is saved and shows on a fresh session.
  final restoredModule = FitnessModule(userId: 'guided-account');
  await restoredModule.ready;
  expect(
    restoredModule.categoryDurations['Core'],
    greaterThan(Duration.zero),
  );
  await tester.pumpWidget(
    MaterialApp(home: Builder(builder: restoredModule.buildDetailView)),
  );
  await tester.pumpAndSettle();
  expect(find.textContaining('Total '), findsOneWidget);
});

  testWidgets('fitness workouts persist per account', (tester) async {
  SharedPreferences.setMockInitialValues({});
  final firstSession = FitnessModule(userId: 'account-a');
  await firstSession.ready;
  await tester.pumpWidget(
    MaterialApp(home: Builder(builder: firstSession.buildDetailView)),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Add your first workout'));
  await tester.pumpAndSettle();
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'Pullups');
  await tester.enterText(fields.at(1), 'Core and Conditioning');
  await tester.enterText(fields.at(2), '3');
  await tester.enterText(fields.at(3), '10');
  await tester.enterText(fields.at(4), '0');
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
  expect(find.text('Pullups'), findsOneWidget);

  final returningSession = FitnessModule(userId: 'account-a');
  await returningSession.ready;
  expect(returningSession.entries, hasLength(1));

  final otherAccount = FitnessModule(userId: 'account-b');
  await otherAccount.ready;
  expect(otherAccount.entries, isEmpty);
});
}