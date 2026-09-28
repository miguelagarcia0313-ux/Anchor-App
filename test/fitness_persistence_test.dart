import 'package:anchor_app/modules/fitness/fitness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
