import 'package:flutter/widgets.dart';

/// The contract every widget module implements so the dashboard shell
/// can host any of them without special-casing.
///
/// To add a new module: implement this interface, then register an
/// instance of it in `shell/dashboard_screen.dart`. Nothing else in
/// the shell needs to change.
abstract class AnchorModule {
  /// Short unique id, e.g. "finance", "tasks".
  String get id;

  /// Display name shown in the widget picker, e.g. "Finance".
  String get displayName;

  /// Small card shown on the dashboard when the user has this module enabled.
  Widget buildSummaryCard(BuildContext context);

  /// Full screen shown when the user taps the summary card.
  Widget buildDetailView(BuildContext context);
}
