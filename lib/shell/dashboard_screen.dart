import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../shared/anchor_module.dart';
import '../modules/finance/finance_module.dart';
import '../modules/health/health_module.dart';
import '../modules/tasks/tasks_module.dart';
import 'settings_screen.dart';

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
    HealthModule(),
    TasksModule(),
  ];

  Set<String> _enabledModuleIds = {};
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _enabledModuleIds = _allModules.map((module) => module.id).toSet();
  }

  void _toggleModule(String moduleId) {
    setState(() {
      if (_enabledModuleIds.contains(moduleId)) {
        _enabledModuleIds.remove(moduleId);
      } else {
        _enabledModuleIds.add(moduleId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabledModules = _allModules
        .where((module) => _enabledModuleIds.contains(module.id))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedTab == 0 ? 'Anchor' : 'Settings'),
        actions: [
          IconButton(
            onPressed: FirebaseAuth.instance.signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: _selectedTab == 0
          ? _DashboardModuleList(modules: enabledModules)
          : SettingsScreen(
              modules: _allModules,
              enabledModuleIds: _enabledModuleIds,
              onModuleChanged: _toggleModule,
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) {
          setState(() => _selectedTab = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _DashboardModuleList extends StatelessWidget {
  const _DashboardModuleList({required this.modules});

  final List<AnchorModule> modules;

  @override
  Widget build(BuildContext context) {
    if (modules.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No modules enabled. Open Settings to choose one.'),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: modules.length,
      itemBuilder: (context, index) {
        final module = modules[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: module.buildDetailView),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: module.buildSummaryCard(context),
          ),
        );
      },
    );
  }
}
