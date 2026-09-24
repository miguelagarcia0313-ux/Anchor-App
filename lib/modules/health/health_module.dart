import 'package:flutter/material.dart';

import '../../shared/anchor_module.dart';

class HealthModule implements AnchorModule {
  @override
  String get id => 'health';

  @override
  String get displayName => 'Health';

  @override
  Widget buildSummaryCard(BuildContext context) {
    return const Card(
      child: ListTile(
        leading: Icon(Icons.monitor_heart_outlined),
        title: Text('Health'),
        subtitle: Text('Wellbeing and progress in one place'),
        trailing: Icon(Icons.chevron_right),
      ),
    );
  }

  @override
  Widget buildDetailView(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health & Fitness')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Today',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          _MetricCard(
            icon: Icons.water_drop_outlined,
            title: 'Health',
            items: const [
              _Metric(label: 'Water', value: '0 glasses'),
              _Metric(label: 'Sleep', value: 'Not logged'),
            ],
          ),
          const SizedBox(height: 12),
          _MetricCard(
            icon: Icons.fitness_center_outlined,
            title: 'Fitness',
            items: const [
              _Metric(label: 'Workout', value: 'Not logged'),
              _Metric(label: 'Steps', value: '0'),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: const Text('Log an activity'),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.title,
    required this.items,
  });

  final IconData icon;
  final String title;
  final List<_Metric> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Text(title, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 16),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item.label),
                    Text(
                      item.value,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;
}