import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../shared/anchor_module.dart';
import '../modules/finance/finance_module.dart';
import '../modules/fitness/fitness.dart';
import '../modules/health/health_module.dart';
import '../modules/tasks/tasks_module.dart';
import 'module_preferences.dart';
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
    FitnessModule(),
    HealthModule(),
    TasksModule(),

    ///Add new modules here. The module contract ensures that the dashboard
    ///screen doesn't need to know anything about the module's implementation.
  ];

  Set<String> _enabledModuleIds = {};
  int _selectedTab = 0;
  bool _isLoadingPreferences = true;
  final ModulePreferences _modulePreferences = const ModulePreferences();

  @override
  void initState() {
    super.initState();
    _enabledModuleIds = _allModules.map((module) => module.id).toSet();
    _loadModulePreferences();
  }

  void _toggleModule(String moduleId) {
    setState(() {
      if (_enabledModuleIds.contains(moduleId)) {
        _enabledModuleIds.remove(moduleId);
      } else {
        _enabledModuleIds.add(moduleId);
      }
    });
    _saveModulePreferences();
  }

  Future<void> _loadModulePreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _isLoadingPreferences = false);
      }
      return;
    }

    final allModuleIds = _allModules.map((module) => module.id).toSet();
    final enabledModuleIds = await _modulePreferences.load(
      userId: user.uid,
      defaultModuleIds: allModuleIds,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _enabledModuleIds = enabledModuleIds;
      _isLoadingPreferences = false;
    });
  }

  Future<void> _saveModulePreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    await _modulePreferences.save(
      userId: user.uid,
      enabledModuleIds: _enabledModuleIds,
    );
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
      body: _isLoadingPreferences
          ? const Center(child: CircularProgressIndicator())
          : _selectedTab == 0
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
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: module.buildDetailView));
            },
            borderRadius: BorderRadius.circular(12),
            child: module.buildSummaryCard(context),
          ),
        );
      },
    );
  }
}
