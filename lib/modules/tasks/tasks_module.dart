import 'package:flutter/material.dart';
import '../../shared/anchor_module.dart';

class TasksModule implements AnchorModule {
  @override
  String get id => 'tasks';

  @override
  String get displayName => 'Tasks';

  @override
  Widget buildSummaryCard(BuildContext context) {
    // TODO: replace with real task list summary
    return const Card(
      child: ListTile(
        leading: Icon(Icons.check_circle_outline),
        title: Text('Tasks'),
        subtitle: Text('To-dos + reminders go here'),
      ),
    );
  }

  @override
  Widget buildDetailView(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: const Center(child: Text('Tasks detail screen — build here')),
    );
  }
}
