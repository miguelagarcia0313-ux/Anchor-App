import 'package:flutter/material.dart';
import '../shared/anchor_module.dart';
import '../modules/finance/finance_module.dart';
import '../modules/tasks/tasks_module.dart';

/// The dashboard shell — the home screen that hosts whichever modules
/// the user has enabled.
///
/// To add a new module once it's built: add one line to [_allModules].
/// Nothing else on this screen needs to change — that's the whole point
/// of the module contract.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final List<AnchorModule> _allModules = [
    FinanceModule(),
    TasksModule(),
    // Add WorkHoursModule(), HealthModule() here once built.
  ];

  // TODO: persist which modules are enabled/reordered instead of "all on".
  late List<AnchorModule> _enabledModules = List.of(_allModules);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anchor')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _enabledModules.length,
        itemBuilder: (context, index) {
          final module = _enabledModules[index];
          return GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: module.buildDetailView),
              );
            },
            child: module.buildSummaryCard(context),
          );
        },
      ),
    );
  }
}
