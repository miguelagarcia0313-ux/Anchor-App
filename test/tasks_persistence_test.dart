import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anchor_app/modules/tasks/tasks_module.dart';

void main() {
  testWidgets('tasks persist when the module is recreated', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final firstModule = TasksModule();

    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: firstModule.buildDetailView)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Renew passport');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final secondModule = TasksModule();
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: secondModule.buildDetailView)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Renew passport'), findsOneWidget);
  });

  testWidgets('reminder lead time persists when the module is recreated', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final firstModule = TasksModule();

    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: firstModule.buildDetailView)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'Call dentist 3AM Wednesday',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('task_reminder_lead_time_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 minutes before').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final secondModule = TasksModule();
    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: secondModule.buildDetailView)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Notification: 10 minutes before'), findsOneWidget);
    await tester.tap(find.text('Call dentist 3AM Wednesday'));
    await tester.pumpAndSettle();
    expect(
      find.text('10 minutes before'),
      findsOneWidget,
    );
  });
}
