import 'package:flutter/material.dart';

import '../shared/anchor_module.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.modules,
    required this.enabledModuleIds,
    required this.onModuleChanged,
    required this.isDarkMode,
    required this.onDarkModeChanged,
  });

  final List<AnchorModule> modules;
  final Set<String> enabledModuleIds;
  final ValueChanged<String> onModuleChanged;
  final bool isDarkMode;
  final ValueChanged<bool> onDarkModeChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Text('Appearance', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Card(
          child: SwitchListTile(
            value: isDarkMode,
            onChanged: onDarkModeChanged,
            secondary: const Icon(Icons.dark_mode_outlined),
            title: const Text('Dark mode'),
            subtitle: const Text('Use a darker appearance.'),
          ),
        ),
        const SizedBox(height: 12),
        Text('Modules', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text('Choose which modules appear on your dashboard.'),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              for (var index = 0; index < modules.length; index++) ...[
                CheckboxListTile(
                  value: enabledModuleIds.contains(modules[index].id),
                  onChanged: (_) => onModuleChanged(modules[index].id),
                  secondary: Icon(_iconFor(modules[index].id)),
                  title: Text(modules[index].displayName),
                  controlAffinity: ListTileControlAffinity.trailing,
                ),
                if (index < modules.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }

  IconData _iconFor(String moduleId) {
    switch (moduleId) {
      case 'finance':
        return Icons.pie_chart_outline;
      case 'health':
        return Icons.monitor_heart_outlined;
      case 'tasks':
        return Icons.check_circle_outline;
      default:
        return Icons.widgets_outlined;
    }
  }
}
