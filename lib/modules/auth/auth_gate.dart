import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../shell/dashboard_screen.dart';
import 'login_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.isDarkMode,
    required this.onDarkModeChanged,
  });

  final bool isDarkMode;
  final ValueChanged<bool> onDarkModeChanged;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return snapshot.hasData
            ? DashboardScreen(
                isDarkMode: isDarkMode,
                onDarkModeChanged: onDarkModeChanged,
              )
            : const LoginScreen();
      },
    );
  }
}
