import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anchor_app/shell/settings_screen.dart';
import 'package:anchor_app/shell/theme_preferences.dart';

void main() {
  test('dark mode preference defaults to light and persists changes', () async {
    SharedPreferences.setMockInitialValues({});
    const preferences = ThemePreferences();

    expect(await preferences.load(), isFalse);

    await preferences.save(true);

    expect(await preferences.load(), isTrue);
  });

  testWidgets('settings exposes a dark mode switch', (tester) async {
    var darkMode = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            modules: const [],
            enabledModuleIds: const {},
            onModuleChanged: (_) {},
            isDarkMode: darkMode,
            onDarkModeChanged: (enabled) => darkMode = enabled,
          ),
        ),
      ),
    );

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Dark mode'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(darkMode, isTrue);
  });
}
