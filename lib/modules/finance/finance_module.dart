import 'package:flutter/material.dart';
import '../../shared/anchor_module.dart';

class FinanceModule implements AnchorModule {
  @override
  String get id => 'finance';

  @override
  String get displayName => 'Finance';

  @override
  Widget buildSummaryCard(BuildContext context) {
    // TODO: replace with real spend-ring summary (fl_chart)
    return const Card(
      child: ListTile(
        leading: Icon(Icons.pie_chart_outline),
        title: Text('Finance'),
        subtitle: Text('Spend rings + savings projection go here'),
      ),
    );
  }

  @override
  Widget buildDetailView(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finance')),
      body: const Center(child: Text('Finance detail screen — build here')),
    );
  }
}
