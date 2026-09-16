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
}
