import 'package:anchor_app/modules/fitness/fitness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('guided workout times exercises and starts rest between them', (
    tester,
  ) async {
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

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 minutes').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text('Workout 1 of 2'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Resume'), findsOneWidget);
    final currentTimer = find.descendant(
      of: find.byType(Dialog),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            RegExp(r'^0:[0-9]{2}$').hasMatch(widget.data ?? ''),
      ),
    );
    final pausedTime = tester.widget<Text>(currentTimer.first).data;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump();
    expect(tester.widget<Text>(currentTimer.first).data, pausedTime);
    await tester.tap(find.text('Resume'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.text('Rest before workout 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Close workout session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Rest before workout 2'), findsOneWidget);

    await tester.tap(find.text('Skip rest'));
    await tester.pump();
    expect(find.text('Workout 2 of 2'), findsOneWidget);
    expect(find.text('Plank'), findsNWidgets(2));

    await tester.tap(find.text('Start'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(find.text('Workout list complete'), findsOneWidget);
    final durationLabels = find.byWidgetPredicate(
      (widget) =>
          widget is Text && RegExp(r'^0:[0-9]{2}$').hasMatch(widget.data ?? ''),
    );
    expect(durationLabels, findsNWidgets(2));
    expect(find.text('0:00'), findsNothing);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

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
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: firstSession.buildDetailView)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add workout'));
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
