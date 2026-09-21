// test_driver/app.dart
// Instrumented entry point for Appium + Flutter Driver.
// Does NOT modify lib/main.dart -- wraps the real app instead, so this
// stays entirely inside test infrastructure and shouldn't need a
// lib/shared/ review per the README's contributing rules.
//
// Run with:
//   flutter run --target=test_driver/app.dart
//
// Requires flutter_driver as a dev_dependency in pubspec.yaml:
//   dev_dependencies:
//     flutter_driver:
//       sdk: flutter

import 'package:flutter_driver/driver_extension.dart';
import 'package:anchor_app/main.dart' as app;

void main() {
  enableFlutterDriverExtension();
  app.main();
}
