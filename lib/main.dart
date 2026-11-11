import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'modules/auth/auth_gate.dart';
import 'modules/tasks/task_notifications.dart';
import 'shell/theme_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await TaskNotificationService.instance.initialize();
  const themePreferences = ThemePreferences();
  final isDarkMode = await themePreferences.load();
  runApp(
    AnchorApp(initialDarkMode: isDarkMode, themePreferences: themePreferences),
  );
}

class AnchorApp extends StatefulWidget {
  const AnchorApp({
    super.key,
    required this.initialDarkMode,
    required this.themePreferences,
  });

  final bool initialDarkMode;
  final ThemePreferences themePreferences;

  @override
  State<AnchorApp> createState() => _AnchorAppState();
}

class _AnchorAppState extends State<AnchorApp> {
  late bool _isDarkMode = widget.initialDarkMode;

  Future<void> _setDarkMode(bool enabled) async {
    await widget.themePreferences.save(enabled);
    if (!mounted) {
      return;
    }
    setState(() => _isDarkMode = enabled);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anchor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1F4E5F),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF1F4E5F),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: AuthGate(isDarkMode: _isDarkMode, onDarkModeChanged: _setDarkMode),
    );
  }
}
