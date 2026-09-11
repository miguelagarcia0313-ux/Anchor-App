import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anchor_app/modules/auth/login_screen.dart';

void main() {
  testWidgets('login form is shown', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LoginScreen()),
    );

    expect(find.text('Welcome to Anchor'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
