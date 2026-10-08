import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anchor_app/modules/tasks/tasks_module.dart';

Widget _detailApp(TasksModule module) {
  return MaterialApp(
    home: Builder(builder: (context) => module.buildDetailView(context)),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the empty state before any tasks are added', (
    WidgetTester tester,
  ) async {
    final module = TasksModule();

    await tester.pumpWidget(_detailApp(module));
    await tester.pumpAndSettle();

    expect(find.text('Tasks & Reminders'), findsOneWidget);
    expect(find.text('No tasks or reminders yet!'), findsOneWidget);
    expect(find.text('Add a task or reminder to get started.'), findsOneWidget);
    expect(find.text('Add Task/Reminder'), findsOneWidget);
  });

  testWidgets('adds a task and updates its summary card', (
    WidgetTester tester,
  ) async {
    final module = TasksModule();

    await tester.pumpWidget(_detailApp(module));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Task/Reminder'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Call the dentist');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Call the dentist'), findsOneWidget);
    expect(
      find.text(
        MaterialLocalizations.of(tester.element(find.text('Call the dentist')))
            .formatMediumDate(DateTime.now()),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) => module.buildSummaryCard(context)),
      ),
    );

    expect(find.text('1 open · 0 reminders'), findsOneWidget);
  });

  testWidgets('sorts tasks by title', (WidgetTester tester) async {
    final module = TasksModule();

    await tester.pumpWidget(_detailApp(module));
    await tester.pumpAndSettle();
    for (final title in ['Zulu task', 'Alpha task']) {
      await tester.tap(find.text('Add Task/Reminder'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, title);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byKey(const Key('tasks_sort_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title A–Z').last);
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Alpha task')).dy,
      lessThan(tester.getTopLeft(find.text('Zulu task')).dy),
    );
  });

  testWidgets('filters tasks to completed items', (WidgetTester tester) async {
    final module = TasksModule();

    await tester.pumpWidget(_detailApp(module));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Task/Reminder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Finished task');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Task/Reminder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Open task');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tasks_filter_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed').last);
    await tester.pumpAndSettle();

    expect(find.text('Finished task'), findsOneWidget);
    expect(find.text('Open task'), findsNothing);
  });

  testWidgets('filters upcoming tasks and sorts by latest due date', (
    WidgetTester tester,
  ) async {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    final dayAfterTomorrow = now.add(const Duration(days: 2));
    final laterTitle =
        'Later task 11:59PM ${weekdays[dayAfterTomorrow.weekday - 1]}';
    final soonerTitle = 'Sooner task 11:59PM ${weekdays[tomorrow.weekday - 1]}';
    final module = TasksModule();

    await tester.pumpWidget(_detailApp(module));
    await tester.pumpAndSettle();
    for (final title in [laterTitle, soonerTitle]) {
      await tester.tap(find.text('Add Task/Reminder'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, title);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Add Task/Reminder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'No date task');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text(soonerTitle)).dy,
      lessThan(tester.getTopLeft(find.text(laterTitle)).dy),
    );

    await tester.tap(find.byKey(const Key('tasks_sort_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Latest due').last);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text(laterTitle)).dy,
      lessThan(tester.getTopLeft(find.text(soonerTitle)).dy),
    );
    expect(
      tester.getTopLeft(find.text(soonerTitle)).dy,
      lessThan(tester.getTopLeft(find.text('No date task')).dy),
    );

    await tester.tap(find.byKey(const Key('tasks_filter_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upcoming').last);
    await tester.pumpAndSettle();
    expect(find.text(soonerTitle), findsOneWidget);
    expect(find.text(laterTitle), findsOneWidget);
    expect(find.text('No date task'), findsNothing);
  });

  testWidgets('updates a task date from natural language in its title', (
    WidgetTester tester,
  ) async {
    final module = TasksModule();

    await tester.pumpWidget(_detailApp(module));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Task/Reminder'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'Call the dentist 3AM Wednesday',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Call the dentist 3AM Wednesday'), findsOneWidget);
    expect(find.textContaining('at 3:00 AM'), findsOneWidget);
  });

  testWidgets('uses the specific date in a task title', (
    WidgetTester tester,
  ) async {
    final module = TasksModule();

    await tester.pumpWidget(_detailApp(module));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Task/Reminder'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'Submit report 2026-10-08',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final expectedDate = MaterialLocalizations.of(
      tester.element(find.text('Submit report 2026-10-08')),
    ).formatMediumDate(DateTime(2026, 10, 8));
    expect(find.text(expectedDate), findsOneWidget);
  });

  testWidgets('does not save a task with an empty title', (
    WidgetTester tester,
  ) async {
    final module = TasksModule();

    await tester.pumpWidget(_detailApp(module));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Task/Reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.widgetWithText(AlertDialog, 'Add Task/Reminder'),
      findsOneWidget,
    );
    expect(find.text('No tasks or reminders yet!'), findsOneWidget);
  });

  testWidgets('adds reminder metadata and can mark it complete', (
    WidgetTester tester,
  ) async {
    final module = TasksModule();

    await tester.pumpWidget(_detailApp(module));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Task/Reminder'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Take medicine');
    await tester.enterText(find.byType(TextField).last, 'After breakfast');
    await tester.tap(find.text('Set tasks as Reminder'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Take medicine'), findsOneWidget);
    expect(find.textContaining('Reminder · '), findsOneWidget);
    expect(find.textContaining('After breakfast'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) => module.buildSummaryCard(context)),
      ),
    );

    expect(find.text('0 open · 0 reminders'), findsOneWidget);
  });

  testWidgets('deletes a task after confirmation', (WidgetTester tester) async {
    final module = TasksModule();

    await tester.pumpWidget(_detailApp(module));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Task/Reminder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Temporary task');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete item?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Temporary task'), findsNothing);
    expect(find.text('No tasks or reminders yet!'), findsOneWidget);
  });
}
