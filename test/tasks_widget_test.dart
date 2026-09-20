import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anchor_app/modules/tasks/tasks_module.dart';

Widget _detailApp(TasksModule module) {
  return MaterialApp(
    home: Builder(
      builder: (context) => module.buildDetailView(context),
    ),
  );
}

void main() {
  testWidgets('shows the empty state before any tasks are added', (
    WidgetTester tester,
  ) async {
    final module = TasksModule();

    await tester.pumpWidget(_detailApp(module));

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
    await tester.tap(find.text('Add Task/Reminder'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Call the dentist');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Call the dentist'), findsOneWidget);
    expect(find.text('Task'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => module.buildSummaryCard(context),
        ),
      ),
    );

    expect(find.text('1 open · 0 reminders'), findsOneWidget);
  });

  testWidgets('does not save a task with an empty title', (
    WidgetTester tester,
  ) async {
    final module = TasksModule();

    await tester.pumpWidget(_detailApp(module));
    await tester.tap(find.text('Add Task/Reminder'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(find.text('Add Task/Reminder'), findsOneWidget);
    expect(find.text('No tasks or reminders yet!'), findsOneWidget);
  });

  testWidgets('adds reminder metadata and can mark it complete', (
    WidgetTester tester,
  ) async {
    final module = TasksModule();

    await tester.pumpWidget(_detailApp(module));
    await tester.tap(find.text('Add Task/Reminder'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Take medicine');
    await tester.enterText(find.byType(TextField).last, 'After breakfast');
    await tester.tap(find.text('Set tasks as Reminder'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Take medicine'), findsOneWidget);
    expect(find.text('Reminder · After breakfast'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => module.buildSummaryCard(context),
        ),
      ),
    );

    expect(find.text('0 open · 0 reminders'), findsOneWidget);
  });

  testWidgets('deletes a task after confirmation', (WidgetTester tester) async {
    final module = TasksModule();

    await tester.pumpWidget(_detailApp(module));
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
