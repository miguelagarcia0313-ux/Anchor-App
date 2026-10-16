import 'dart:async';
import 'dart:convert';
// ignore: unnecessary_import
import 'dart:ui' show FontFeature;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/anchor_module.dart';
import '../../shared/module_bottom_sheet.dart';
import '../../shared/user_cloud_sync.dart';

int _idSequence = 0;

/// Unique even when two workouts are created within the same microsecond.
String _newWorkoutId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${_idSequence++}';

class WorkoutEntry {
  WorkoutEntry({
    required this.id,
    required this.name,
    required this.category,
    required this.sets,
    required this.reps,
    required this.minimumWeight,
  });

  final String id;
  String name;
  String category;
  int sets;
  int reps;
  double minimumWeight;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'category': category,
    'sets': sets,
    'reps': reps,
    'minimumWeight': minimumWeight,
  };

  factory WorkoutEntry.fromMap(Map<String, dynamic> map) {
    return WorkoutEntry(
      id: map['id'] as String,
      name: map['name'] as String,
      category: map['category'] as String,
      sets: map['sets'] as int,
      reps: map['reps'] as int,
      minimumWeight: (map['minimumWeight'] as num).toDouble(),
    );
  }
}

class FitnessModule implements AnchorModule {
  FitnessModule({String? userId})
    : _userIdOverride = userId,
      _cloud = UserCloudSync.forCurrentUser(userIdOverride: userId);

  static const _legacyStorageKey = 'fitness.workouts';
  static const _legacyMigrationKey = 'fitness.userScopedMigrationComplete';

  final String? _userIdOverride;

  late final String userId =
      _userIdOverride ??
      (Firebase.apps.isEmpty
          ? 'local'
          : FirebaseAuth.instance.currentUser?.uid ?? 'local');

  String get _storageKey => 'fitness.$userId.workouts';
  String get _categoryDurationsKey => 'fitness.$userId.categoryDurations';
  String get _displayOrderKey => 'fitness.$userId.displayOrder';

  final List<WorkoutEntry> _entries = [];
  final List<String> _categoryOrder = [];
  final List<String> _workoutOrder = [];
  final Map<String, Duration> _categoryDurations = {};
  final ValueNotifier<int> _revision = ValueNotifier(0);
  final UserCloudSync? _cloud;
  bool _hasReceivedWorkoutSnapshot = false;
  late final Future<void> _ready = _loadEntries();

  @override
  String get id => 'fitness';

  @override
  String get displayName => 'Fitness';

  Future<void> get ready => _ready;

  @override
  Widget buildSummaryCard(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _revision,
      builder: (context, revision, child) {
        final workoutCount = _entries.length;
        return Card(
          child: ListTile(
            leading: const Icon(Icons.fitness_center_outlined),
            title: const Text('Fitness'),
            subtitle: Text(
              workoutCount == 0
                  ? 'Add workouts by category'
                  : '$workoutCount workout${workoutCount == 1 ? '' : 's'} saved',
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }

  @override
  Widget buildDetailView(BuildContext context) {
    return _FitnessDetailView(module: this);
  }

  List<WorkoutEntry> get entries => List.unmodifiable(_entries);

  List<String> get categories => List.unmodifiable(_categoryOrder);

  List<WorkoutEntry> entriesForCategory(String category) {
    return List.unmodifiable(
      _entries.where((entry) => entry.category == category).toList()..sort(
        (first, second) => _workoutOrder
            .indexOf(first.id)
            .compareTo(_workoutOrder.indexOf(second.id)),
      ),
    );
  }

  Future<void> reorderCategories(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _categoryOrder.length ||
        newIndex < 0 ||
        newIndex >= _categoryOrder.length ||
        oldIndex == newIndex) {
      return;
    }
    final category = _categoryOrder.removeAt(oldIndex);
    _categoryOrder.insert(newIndex, category);
    _notifyChanged();
    await _persistDisplayOrder();
  }

  Future<void> reorderWorkouts(
    String category,
    int oldIndex,
    int newIndex,
  ) async {
    final categoryEntries = entriesForCategory(category).toList();
    if (oldIndex < 0 ||
        oldIndex >= categoryEntries.length ||
        newIndex < 0 ||
        newIndex >= categoryEntries.length ||
        oldIndex == newIndex) {
      return;
    }
    final entry = categoryEntries.removeAt(oldIndex);
    categoryEntries.insert(newIndex, entry);
    final movedIds = categoryEntries.map((entry) => entry.id).toList();
    final categoryIds = categoryEntries.map((entry) => entry.id).toSet();
    var movedIndex = 0;
    for (var index = 0; index < _workoutOrder.length; index++) {
      if (categoryIds.contains(_workoutOrder[index])) {
        _workoutOrder[index] = movedIds[movedIndex++];
      }
    }
    _notifyChanged();
    await _persistDisplayOrder();
  }

  Map<String, Duration> get categoryDurations =>
      Map.unmodifiable(_categoryDurations);

  void updateCategoryDuration(String category, Duration duration) {
    _categoryDurations[category] = duration;
  }

  Future<void> persistCategoryDurations() async {
    final preferences = await SharedPreferences.getInstance();
    final encodedDurations = _categoryDurations.map(
      (category, duration) => MapEntry(category, duration.inSeconds),
    );
    await preferences.setString(
      _categoryDurationsKey,
      jsonEncode(encodedDurations),
    );
    if (_cloud != null) {
      await _cloud
          .moduleDocument('fitness')
          .collection('settings')
          .doc('categoryDurations')
          .set({'durations': encodedDurations});
    }
  }

  Future<void> addEntry(WorkoutDraft draft) async {
    final entry = WorkoutEntry(
      id: _newWorkoutId(),
      name: draft.name,
      category: draft.category,
      sets: draft.sets,
      reps: draft.reps,
      minimumWeight: draft.minimumWeight,
    );
    _entries.add(entry);
    _reconcileDisplayOrder();
    _notifyChanged();
    await _persistEntries();
    await _persistDisplayOrder();
    await _persistCloudEntry(entry);
  }

  Future<void> updateEntry(WorkoutEntry entry, WorkoutDraft draft) async {
    final previousCategory = entry.category;
    entry
      ..name = draft.name
      ..category = draft.category
      ..sets = draft.sets
      ..reps = draft.reps
      ..minimumWeight = draft.minimumWeight;
    if (previousCategory != entry.category) {
      _workoutOrder.remove(entry.id);
      _workoutOrder.add(entry.id);
    }
    _reconcileDisplayOrder();
    _notifyChanged();
    await _persistEntries();
    await _persistDisplayOrder();
    await _persistCloudEntry(entry);
  }

  Future<void> deleteEntry(WorkoutEntry entry) async {
    _entries.remove(entry);
    _reconcileDisplayOrder();
    _notifyChanged();
    await _persistEntries();
    await _persistDisplayOrder();
    await _cloud?.records('fitness', 'workouts').doc(entry.id).delete();
  }

  Future<void> restoreEntry(WorkoutEntry entry, int categoryIndex) async {
    if (_entries.any((existing) => existing.id == entry.id)) return;
    _entries.add(entry);
    _reconcileDisplayOrder();
    _notifyChanged();
    await _persistEntries();
    await _persistDisplayOrder();
    await _persistCloudEntry(entry);
    final count = entriesForCategory(entry.category).length;
    if (categoryIndex >= 0 && categoryIndex < count - 1) {
      await reorderWorkouts(entry.category, count - 1, categoryIndex);
    }
  }

  Future<void> _loadEntries() async {
    final preferences = await SharedPreferences.getInstance();
    if (!(preferences.getBool(_legacyMigrationKey) ?? false)) {
      final legacyEntries = preferences.getStringList(_legacyStorageKey);
      if (!preferences.containsKey(_storageKey) && legacyEntries != null) {
        await preferences.setStringList(_storageKey, legacyEntries);
      }
      await preferences.remove(_legacyStorageKey);
      await preferences.setBool(_legacyMigrationKey, true);
    }
    final storedEntries = preferences.getStringList(_storageKey) ?? [];
    _entries
      ..clear()
      ..addAll(
        storedEntries.map(
          (encodedEntry) => WorkoutEntry.fromMap(
            jsonDecode(encodedEntry) as Map<String, dynamic>,
          ),
        ),
      );
    final storedOrder = preferences.getString(_displayOrderKey);
    if (storedOrder != null) {
      final order = jsonDecode(storedOrder) as Map<String, dynamic>;
      _categoryOrder
        ..clear()
        ..addAll((order['categories'] as List<dynamic>? ?? []).cast<String>());
      _workoutOrder
        ..clear()
        ..addAll((order['workouts'] as List<dynamic>? ?? []).cast<String>());
    }
    _reconcileDisplayOrder();
    final storedDurations = preferences.getString(_categoryDurationsKey);
    if (storedDurations != null) {
      final decoded = jsonDecode(storedDurations) as Map<String, dynamic>;
      _categoryDurations
        ..clear()
        ..addAll(
          decoded.map(
            (category, seconds) =>
                MapEntry(category, Duration(seconds: (seconds as num).toInt())),
          ),
        );
    }
    _notifyChanged();
    final cloud = _cloud;
    if (cloud == null) return;

    await cloud.migrateLocalDataOnce('fitness', () async {
      await cloud.setRecords(
        'fitness',
        'workouts',
        _entries.map((entry) => MapEntry(entry.id, entry.toMap())),
      );
      await cloud
          .moduleDocument('fitness')
          .collection('settings')
          .doc('categoryDurations')
          .set({
            'durations': _categoryDurations.map(
              (category, duration) => MapEntry(category, duration.inSeconds),
            ),
          });
      await cloud
          .moduleDocument('fitness')
          .collection('settings')
          .doc('displayOrder')
          .set({'categories': _categoryOrder, 'workouts': _workoutOrder});
    });

    cloud
        .records('fitness', 'workouts')
        .snapshots()
        .listen(
          (snapshot) {
            _entries
              ..clear()
              ..addAll(
                snapshot.docs.map((document) {
                  return WorkoutEntry.fromMap(document.data());
                }),
              );
            _hasReceivedWorkoutSnapshot = true;
            _reconcileDisplayOrder();
            _notifyChanged();
            unawaited(_persistEntries());
            unawaited(_persistDisplayOrder(syncCloud: false));
          },
          onError: (Object error, StackTrace stackTrace) {
            cloud.reportStreamError('fitness', error, stackTrace);
          },
        );
    cloud
        .moduleDocument('fitness')
        .collection('settings')
        .doc('displayOrder')
        .snapshots()
        .listen(
          (snapshot) {
            final data = snapshot.data();
            if (data != null) {
              _categoryOrder
                ..clear()
                ..addAll(
                  (data['categories'] as List<dynamic>? ?? []).cast<String>(),
                );
              _workoutOrder
                ..clear()
                ..addAll(
                  (data['workouts'] as List<dynamic>? ?? []).cast<String>(),
                );
            }
            if (_hasReceivedWorkoutSnapshot) {
              _reconcileDisplayOrder();
              _notifyChanged();
              unawaited(_persistDisplayOrder(syncCloud: data == null));
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            cloud.reportStreamError('fitness', error, stackTrace);
          },
        );
    cloud
        .moduleDocument('fitness')
        .collection('settings')
        .doc('categoryDurations')
        .snapshots()
        .listen(
          (snapshot) {
            final durations =
                snapshot.data()?['durations'] as Map<String, dynamic>? ?? {};
            _categoryDurations
              ..clear()
              ..addAll(
                durations.map(
                  (category, seconds) => MapEntry(
                    category,
                    Duration(seconds: (seconds as num).toInt()),
                  ),
                ),
              );
            _notifyChanged();
            unawaited(_persistCategoryDurationsLocally());
          },
          onError: (Object error, StackTrace stackTrace) {
            cloud.reportStreamError('fitness', error, stackTrace);
          },
        );
  }

  void _reconcileDisplayOrder() {
    final activeCategories = _entries.map((entry) => entry.category).toSet();
    _categoryOrder.removeWhere(
      (category) => !activeCategories.contains(category),
    );
    final missingCategories =
        activeCategories
            .where((category) => !_categoryOrder.contains(category))
            .toList()
          ..sort();
    _categoryOrder.addAll(missingCategories);

    final activeWorkoutIds = _entries.map((entry) => entry.id).toSet();
    _workoutOrder.removeWhere((id) => !activeWorkoutIds.contains(id));
    final missingWorkouts =
        _entries.where((entry) => !_workoutOrder.contains(entry.id)).toList()
          ..sort((first, second) {
            final categoryOrder = first.category.compareTo(second.category);
            if (categoryOrder != 0) return categoryOrder;
            final nameOrder = first.name.compareTo(second.name);
            return nameOrder != 0 ? nameOrder : first.id.compareTo(second.id);
          });
    _workoutOrder.addAll(missingWorkouts.map((entry) => entry.id));
  }

  Future<void> _persistDisplayOrder({bool syncCloud = true}) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _displayOrderKey,
      jsonEncode({'categories': _categoryOrder, 'workouts': _workoutOrder}),
    );
    if (syncCloud) {
      await _cloud
          ?.moduleDocument('fitness')
          .collection('settings')
          .doc('displayOrder')
          .set({'categories': _categoryOrder, 'workouts': _workoutOrder});
    }
  }

  Future<void> _persistEntries() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _storageKey,
      _entries.map((entry) => jsonEncode(entry.toMap())).toList(),
    );
  }

  Future<void> _persistCategoryDurationsLocally() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _categoryDurationsKey,
      jsonEncode(
        _categoryDurations.map(
          (category, duration) => MapEntry(category, duration.inSeconds),
        ),
      ),
    );
  }

  Future<void> _persistCloudEntry(WorkoutEntry entry) async {
    await _cloud
        ?.records('fitness', 'workouts')
        .doc(entry.id)
        .set(entry.toMap());
  }

  void _notifyChanged() {
    _revision.value++;
  }
}

class WorkoutDraft {
  const WorkoutDraft({
    required this.name,
    required this.category,
    required this.sets,
    required this.reps,
    required this.minimumWeight,
  });

  final String name;
  final String category;
  final int sets;
  final int reps;
  final double minimumWeight;
}

class _FitnessDetailView extends StatefulWidget {
  const _FitnessDetailView({required this.module});

  final FitnessModule module;

  @override
  State<_FitnessDetailView> createState() => _FitnessDetailViewState();
}

class _FitnessDetailViewState extends State<_FitnessDetailView> {
  _GuidedWorkoutSession? _activeSession;
  final Map<String, Duration> _categoryDurations = {};
  final Set<String> _collapsedCategories = {};
  Timer? _sessionTicker;

  @override
  void initState() {
    super.initState();
    widget.module._revision.addListener(_handleModuleChanged);
    widget.module.ready.then((_) {
      _handleModuleChanged();
    });
  }

  void _handleModuleChanged() {
    if (!mounted) return;
    setState(() {
      _categoryDurations
        ..clear()
        ..addAll(widget.module.categoryDurations);
    });
  }

  @override
  void dispose() {
    widget.module._revision.removeListener(_handleModuleChanged);
    _sessionTicker?.cancel();
    super.dispose();
  }

  Future<void> _addWorkout() async {
    final draft = await showModalBottomSheet<WorkoutDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          _WorkoutEditorDialog(categories: widget.module.categories),
    );
    if (draft != null) {
      await widget.module.addEntry(draft);
      setState(() {});
    }
  }

  Future<void> _editWorkout(WorkoutEntry entry) async {
    final draft = await showModalBottomSheet<WorkoutDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _WorkoutEditorDialog(
        entry: entry,
        categories: widget.module.categories,
      ),
    );
    if (draft != null) {
      await widget.module.updateEntry(entry, draft);
      setState(() {});
    }
  }

  Future<void> _deleteWithUndo(WorkoutEntry entry) async {
    final categoryIndex = widget.module
        .entriesForCategory(entry.category)
        .indexWhere((candidate) => candidate.id == entry.id);
    final messenger = ScaffoldMessenger.of(context);
    final deletion = widget.module.deleteEntry(entry);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Deleted "${entry.name}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () =>
                unawaited(widget.module.restoreEntry(entry, categoryIndex)),
          ),
        ),
      );
    await deletion;
  }

  Future<void> _startGuidedWorkout() async {
    final categories = widget.module.categories;
    var session = _activeSession;
    if (session != null) {
      final choice = await showModalBottomSheet<_SessionReturnChoice>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => ModuleBottomSheet(
          title: 'Workout session saved',
          actions: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(context, _SessionReturnChoice.reset),
                child: const Text('Reset'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _SessionReturnChoice.continueSession,
                ),
                child: const Text('Continue'),
              ),
            ],
          ),
          child: Text(
            'Continue ${session!.category} where you left off, or reset and '
            'start a new workout timing?',
          ),
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == _SessionReturnChoice.reset) session = null;
    }

    if (session == null) {
      if (categories.isEmpty) return;
      final setup = await showModalBottomSheet<_GuidedWorkoutSetup>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => _WorkoutSetupDialog(
          categories: categories,
          workoutsFor: widget.module.entriesForCategory,
        ),
      );
      if (setup == null || !mounted) return;

      final allWorkouts = widget.module.entriesForCategory(setup.category);
      if (allWorkouts.isEmpty) return;
      final startIndex = setup.startIndex
          .clamp(0, allWorkouts.length - 1)
          .toInt();

      session = _GuidedWorkoutSession(
        category: setup.category,
        workouts: allWorkouts,
        setRestSeconds: setup.setRestSeconds,
        workoutRestSeconds: setup.workoutRestSeconds,
      )..chooseWorkout(allWorkouts[startIndex]);
      _sessionTicker?.cancel();
      _sessionTicker = null;
      _activeSession = session;
      _categoryDurations[setup.category] = Duration.zero;
      widget.module.updateCategoryDuration(setup.category, Duration.zero);
      await widget.module.persistCategoryDurations();
      if (!mounted) return;
      setState(() {});
    }

    final selectedSession = session;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => _GuidedWorkoutDialog(
        session: selectedSession,
        onSessionChanged: (persist) =>
            _updateSessionTotal(selectedSession, persist: persist),
        onFinish: () => _finishSession(selectedSession),
      ),
    );
  }

  void _updateSessionTotal(
    _GuidedWorkoutSession session, {
    required bool persist,
  }) {
    if (!mounted) return;
    _categoryDurations[session.category] = session.totalDuration;
    widget.module.updateCategoryDuration(
      session.category,
      session.totalDuration,
    );
    if (persist) unawaited(widget.module.persistCategoryDurations());
    setState(() {});

    if (session.isRunning || session.isResting) {
      _sessionTicker ??= Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (session.isResting) session.advanceRestIfComplete();
        _categoryDurations[session.category] = session.totalDuration;
        widget.module.updateCategoryDuration(
          session.category,
          session.totalDuration,
        );
        setState(() {});
        if (!session.isRunning && !session.isResting) {
          timer.cancel();
          _sessionTicker = null;
        }
      });
    } else {
      _sessionTicker?.cancel();
      _sessionTicker = null;
    }
  }

  Future<void> _finishSession(_GuidedWorkoutSession session) async {
    _sessionTicker?.cancel();
    _sessionTicker = null;
    if (!mounted) return;
    widget.module.updateCategoryDuration(
      session.category,
      session.totalDuration,
    );
    unawaited(widget.module.persistCategoryDurations());
    setState(() {
      _categoryDurations[session.category] = session.totalDuration;
      if (identical(_activeSession, session)) _activeSession = null;
    });
    await widget.module.persistCategoryDurations();
  }

  Widget _dragProxy(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(animation.value);
        return Material(
          elevation: 10 * t,
          color: Colors.transparent,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(16),
          child: child,
        );
      },
      child: child,
    );
  }

  Widget _buildCategoryGroup(String category, int index) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final workouts = widget.module.entriesForCategory(category);
    final isCollapsed = _collapsedCategories.contains(category);
    final total = _categoryDurations[category];

    return Card(
      key: ValueKey('category:$category'),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            leading: ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle),
            ),
            title: Text(
              category,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _StatChip(
                    Icons.list_alt_outlined,
                    '${workouts.length} workout'
                    '${workouts.length == 1 ? '' : 's'}',
                  ),
                  if (total != null && total > Duration.zero)
                    _StatChip(
                      Icons.timer_outlined,
                      'Total ${_formatDuration(total)}',
                    ),
                ],
              ),
            ),
            trailing: AnimatedRotation(
              turns: isCollapsed ? 0.5 : 0,
              duration: const Duration(milliseconds: 250),
              child: const Icon(Icons.expand_less),
            ),
            onTap: () => setState(() {
              if (!_collapsedCategories.add(category)) {
                _collapsedCategories.remove(category);
              }
            }),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: isCollapsed
                ? const SizedBox(width: double.infinity)
                : ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    proxyDecorator: _dragProxy,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    itemCount: workouts.length,
                    // onReorderItem already adjusts newIndex for the removed
                    // item, so no manual "newIndex -= 1" is needed.
                    onReorderItem: (oldIndex, newIndex) {
                      unawaited(
                        widget.module.reorderWorkouts(
                          category,
                          oldIndex,
                          newIndex,
                        ),
                      );
                    },
                    itemBuilder: (context, workoutIndex) => _buildWorkoutTile(
                      workouts[workoutIndex],
                      workoutIndex,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutTile(WorkoutEntry entry, int index) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      key: ValueKey('workout:${entry.id}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey('dismiss:${entry.id}'),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => unawaited(_deleteWithUndo(entry)),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
        ),
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: scheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            leading: ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle),
            ),
            title: Text(
              entry.name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _WorkoutStats(entry),
            ),
            trailing: Icon(
              Icons.edit_outlined,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            onTap: () => _editWorkout(entry),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fitness_center,
              size: 72,
              color: theme.colorScheme.primary.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text('No workouts yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Create a workout list to track sets, reps and rest.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _addWorkout,
              icon: const Icon(Icons.add),
              label: const Text('Add your first workout'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.module.categories;

    return Scaffold(
      appBar: AppBar(title: const Text('Fitness')),
      body: categories.isEmpty
          ? _buildEmptyState(context)
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _startGuidedWorkout,
                      icon: const Icon(Icons.play_arrow, size: 28),
                      label: const Text('Start workout'),
                    ),
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    buildDefaultDragHandles: false,
                    proxyDecorator: _dragProxy,
                    itemCount: categories.length,
                    // onReorderItem already adjusts newIndex for the removed
                    // item, so no manual "newIndex -= 1" is needed.
                    onReorderItem: (oldIndex, newIndex) {
                      unawaited(
                        widget.module.reorderCategories(oldIndex, newIndex),
                      );
                    },
                    itemBuilder: (context, index) =>
                        _buildCategoryGroup(categories[index], index),
                  ),
                ),
              ],
            ),
      floatingActionButton: categories.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _addWorkout,
              icon: const Icon(Icons.add),
              label: const Text('Add workout'),
            ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkoutStats extends StatelessWidget {
  const _WorkoutStats(this.entry, {this.alignment = WrapAlignment.start});

  final WorkoutEntry entry;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: alignment,
      children: [
        _StatChip(Icons.repeat, '${entry.sets} sets'),
        _StatChip(Icons.tag, '${entry.reps} reps'),
        _StatChip(
          Icons.fitness_center,
          '${_formatWeight(entry.minimumWeight)} lb min',
        ),
      ],
    );
  }
}

enum _SessionReturnChoice { continueSession, reset }

class _GuidedWorkoutSetup {
  const _GuidedWorkoutSetup({
    required this.category,
    required this.startIndex,
    required this.setRestSeconds,
    required this.workoutRestSeconds,
  });

  final String category;
  final int startIndex;
  final int setRestSeconds;
  final int workoutRestSeconds;
}

class _GuidedWorkoutSession {
  _GuidedWorkoutSession({
    required this.category,
    required this.workouts,
    required this.setRestSeconds,
    required this.workoutRestSeconds,
  });

  final String category;
  final List<WorkoutEntry> workouts;
  final int setRestSeconds;
  final int workoutRestSeconds;
  final Stopwatch _stopwatch = Stopwatch();
  final Map<String, Duration> completedDurations = {};
  final List<WorkoutEntry> completedWorkouts = [];
  WorkoutEntry? currentWorkout;
  int completedSets = 0;
  bool _startedCurrentWorkout = false;
  bool _endedEarly = false;
  DateTime? restEndsAt;
  bool restIsBetweenWorkouts = false;
  int restTotalSeconds = 0;

  List<WorkoutEntry> get remainingWorkouts => workouts
      .where(
        (workout) =>
            !completedDurations.containsKey(workout.id) &&
            workout.id != currentWorkout?.id,
      )
      .toList();

  bool get isComplete =>
      _endedEarly ||
      (currentWorkout == null && !isResting && remainingWorkouts.isEmpty);
  bool get isChoosingNext => currentWorkout == null && !isResting && !isComplete;
  bool get isRunning => _stopwatch.isRunning;
  bool get isResting => restEndsAt != null;
  bool get hasStartedCurrentWorkout => _startedCurrentWorkout;
  Duration get currentElapsed => _stopwatch.elapsed;
  int get currentSetNumber => completedSets + 1;

  Duration get restRemaining {
    final end = restEndsAt;
    if (end == null) return Duration.zero;
    final remaining = end.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration get totalDuration {
    final completed = completedDurations.values.fold<Duration>(
      Duration.zero,
      (total, duration) => total + duration,
    );
    return completed +
        (_startedCurrentWorkout ? _stopwatch.elapsed : Duration.zero);
  }

  void chooseWorkout(WorkoutEntry workout) {
    currentWorkout = workout;
    completedSets = 0;
    _startedCurrentWorkout = false;
    _stopwatch.reset();
  }

  void startOrResumeWorkout() {
    if (!_startedCurrentWorkout) {
      _stopwatch.reset();
      _startedCurrentWorkout = true;
    }
    _stopwatch.start();
  }

  void pauseWorkout() => _stopwatch.stop();

  /// Marks the current set as done. Rests between sets; after the final set,
  /// rests between workouts and then lets the user pick what comes next.
  void finishSet() {
    final workout = currentWorkout;
    if (workout == null) return;
    completedSets++;
    if (completedSets >= workout.sets) {
      _stopwatch.stop();
      completedDurations[workout.id] = _stopwatch.elapsed;
      completedWorkouts.add(workout);
      currentWorkout = null;
      _startedCurrentWorkout = false;
      completedSets = 0;
      if (remainingWorkouts.isEmpty) {
        restEndsAt = null;
      } else {
        restIsBetweenWorkouts = true;
        restTotalSeconds = workoutRestSeconds;
        restEndsAt = DateTime.now().add(Duration(seconds: workoutRestSeconds));
      }
    } else {
      restIsBetweenWorkouts = false;
      restTotalSeconds = setRestSeconds;
      restEndsAt = DateTime.now().add(Duration(seconds: setRestSeconds));
    }
  }

  bool advanceRestIfComplete() {
    final end = restEndsAt;
    if (end == null || DateTime.now().isBefore(end)) return false;
    restEndsAt = null;
    return true;
  }

  void skipRest() => restEndsAt = null;

  void endEarly() {
    _stopwatch.stop();
    restEndsAt = null;
    _endedEarly = true;
  }
}

class _WorkoutSetupDialog extends StatefulWidget {
  const _WorkoutSetupDialog({
    required this.categories,
    required this.workoutsFor,
  });

  final List<String> categories;
  final List<WorkoutEntry> Function(String category) workoutsFor;

  @override
  State<_WorkoutSetupDialog> createState() => _WorkoutSetupDialogState();
}

class _WorkoutSetupDialogState extends State<_WorkoutSetupDialog> {
  static const _setRestOptions = [30, 45, 60, 90, 120, 180, 240, 300];
  static const _workoutRestOptions = [60, 90, 120, 180, 240, 300, 420, 600];

  late String _category = widget.categories.first;
  int _startIndex = 0;
  int _setRestSeconds = 60;
  int _workoutRestSeconds = 120;

  String _restLabel(int seconds) {
    if (seconds < 60) return '$seconds seconds';
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    final minuteText = '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
    return remainder == 0 ? minuteText : '$minutes min $remainder sec';
  }

  Widget _restDropdown({
    required String label,
    required List<int> options,
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: options
          .map(
            (seconds) => DropdownMenuItem(
              value: seconds,
              child: Text(_restLabel(seconds)),
            ),
          )
          .toList(),
      onChanged: (seconds) {
        if (seconds != null) onChanged(seconds);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final workouts = widget.workoutsFor(_category);
    return ModuleBottomSheet(
      title: 'Set up guided workout',
      actions: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _GuidedWorkoutSetup(
                category: _category,
                startIndex: _startIndex,
                setRestSeconds: _setRestSeconds,
                workoutRestSeconds: _workoutRestSeconds,
              ),
            ),
            child: const Text('Start'),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Workout list'),
            items: widget.categories
                .map(
                  (category) =>
                      DropdownMenuItem(value: category, child: Text(category)),
                )
                .toList(),
            onChanged: (category) {
              if (category != null) {
                setState(() {
                  _category = category;
                  _startIndex = 0;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            key: ValueKey('start:$_category'),
            initialValue: _startIndex,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Start with'),
            items: [
              for (var index = 0; index < workouts.length; index++)
                DropdownMenuItem(
                  value: index,
                  child: Text(
                    '${index + 1}. ${workouts[index].name}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (index) {
              if (index != null) setState(() => _startIndex = index);
            },
          ),
          const SizedBox(height: 16),
          _restDropdown(
            label: 'Rest between sets',
            options: _setRestOptions,
            value: _setRestSeconds,
            onChanged: (seconds) => setState(() => _setRestSeconds = seconds),
          ),
          const SizedBox(height: 16),
          _restDropdown(
            label: 'Rest between workouts',
            options: _workoutRestOptions,
            value: _workoutRestSeconds,
            onChanged: (seconds) =>
                setState(() => _workoutRestSeconds = seconds),
          ),
        ],
      ),
    );
  }
}

enum _SessionPhase { work, rest, pick, done }

TextStyle? _timerStyle(BuildContext context) {
  return Theme.of(context).textTheme.displayMedium?.copyWith(
    fontWeight: FontWeight.w700,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

class _SetDots extends StatelessWidget {
  const _SetDots({required this.total, required this.completed});

  final int total;
  final int completed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var index = 0; index < total; index++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: index == completed ? 28 : 12,
            height: 12,
            decoration: BoxDecoration(
              color: index < completed
                  ? scheme.primary
                  : index == completed
                  ? Colors.transparent
                  : scheme.onPrimaryContainer.withValues(alpha: 0.18),
              border: index == completed
                  ? Border.all(color: scheme.primary, width: 2)
                  : null,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

class _GuidedWorkoutDialog extends StatefulWidget {
  const _GuidedWorkoutDialog({
    required this.session,
    required this.onSessionChanged,
    required this.onFinish,
  });

  final _GuidedWorkoutSession session;
  final ValueChanged<bool> onSessionChanged;
  final Future<void> Function() onFinish;

  @override
  State<_GuidedWorkoutDialog> createState() => _GuidedWorkoutDialogState();
}

class _GuidedWorkoutDialogState extends State<_GuidedWorkoutDialog> {
  Timer? _ticker;
  late bool _wasResting = widget.session.isResting;

  @override
  void initState() {
    super.initState();
    widget.session.advanceRestIfComplete();
    _wasResting = widget.session.isResting;
    _syncTicker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSessionChanged(true);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _apply(VoidCallback change, [VoidCallback? haptic]) {
    change();
    _wasResting = widget.session.isResting;
    haptic?.call();
    _syncTicker();
    setState(() {});
    widget.onSessionChanged(true);
  }

  void _startWorkout() =>
      _apply(widget.session.startOrResumeWorkout, HapticFeedback.lightImpact);
  void _pauseWorkout() => _apply(widget.session.pauseWorkout);
  void _finishSet() =>
      _apply(widget.session.finishSet, HapticFeedback.mediumImpact);
  void _skipRest() => _apply(widget.session.skipRest);
  void _endEarly() => _apply(widget.session.endEarly);
  void _chooseWorkout(WorkoutEntry workout) => _apply(
    () => widget.session.chooseWorkout(workout),
    HapticFeedback.selectionClick,
  );

  void _syncTicker() {
    _ticker?.cancel();
    if (widget.session.isRunning || widget.session.isResting) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        widget.session.advanceRestIfComplete();
        if (_wasResting && !widget.session.isResting) {
          HapticFeedback.heavyImpact();
        }
        _wasResting = widget.session.isResting;
        setState(() {});
        widget.onSessionChanged(false);
      });
    }
  }

  _SessionPhase get _phase {
    final session = widget.session;
    if (session.isComplete) return _SessionPhase.done;
    if (session.isResting) return _SessionPhase.rest;
    if (session.isChoosingNext) return _SessionPhase.pick;
    return _SessionPhase.work;
  }

  String get _phaseKey {
    final session = widget.session;
    return switch (_phase) {
      _SessionPhase.work => 'work:${session.currentWorkout?.id}',
      _SessionPhase.rest =>
        'rest:${session.restIsBetweenWorkouts}:${session.completedSets}:'
            '${session.completedWorkouts.length}',
      _SessionPhase.pick => 'pick:${session.completedWorkouts.length}',
      _SessionPhase.done => 'done',
    };
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (tint, onTint) = switch (_phase) {
      _SessionPhase.work => (scheme.primaryContainer, scheme.onPrimaryContainer),
      _SessionPhase.rest => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      _SessionPhase.pick => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      _SessionPhase.done => (scheme.primaryContainer, scheme.onPrimaryContainer),
    };
    final tintedTheme = theme.copyWith(
      textTheme: theme.textTheme.apply(bodyColor: onTint, displayColor: onTint),
    );

    return ModuleBottomSheet(
      title: session.category,
      titleAction: IconButton(
        tooltip: 'Close workout session',
        onPressed: () {
          widget.onSessionChanged(true);
          Navigator.pop(context);
        },
        icon: const Icon(Icons.close),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildOverallProgress(context),
          const SizedBox(height: 12),
          Theme(
            data: tintedTheme,
            child: Builder(
              builder: (context) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.topCenter,
                      children: [?current],
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_phaseKey),
                      child: switch (_phase) {
                        _SessionPhase.done => _buildCompletionSummary(context),
                        _SessionPhase.rest => _buildRestView(context),
                        _SessionPhase.pick => _buildPickNextView(context),
                        _SessionPhase.work => _buildWorkoutView(context),
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallProgress(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);
    final current = session.currentWorkout;
    final inWorkout = current == null ? 0.0 : session.completedSets / current.sets;
    final total = session.workouts.length;
    final progress = session.isComplete
        ? 1.0
        : ((session.completedWorkouts.length + inWorkout) / total)
              .clamp(0.0, 1.0)
              .toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${session.completedWorkouts.length} of $total workouts done',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: progress),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            builder: (context, value, _) =>
                LinearProgressIndicator(value: value, minHeight: 8),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCompletedList() {
    final session = widget.session;
    if (session.completedWorkouts.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      const Divider(),
      ...session.completedWorkouts.map((workout) {
        final duration = session.completedDurations[workout.id];
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.check_circle_outline),
          title: Text(workout.name),
          trailing: Text(_formatDuration(duration ?? Duration.zero)),
        );
      }),
    ];
  }

  Widget _buildWorkoutView(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);
    final workout = session.currentWorkout!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Workout ${session.completedWorkouts.length + 1} of '
          '${session.workouts.length}',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Text(
          workout.name,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        _WorkoutStats(workout, alignment: WrapAlignment.center),
        const SizedBox(height: 20),
        _SetDots(total: workout.sets, completed: session.completedSets),
        const SizedBox(height: 8),
        Text(
          'Set ${session.currentSetNumber} of ${workout.sets}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 16),
        Text(
          _formatDuration(session.currentElapsed),
          textAlign: TextAlign.center,
          style: _timerStyle(context),
        ),
        const SizedBox(height: 16),
        if (session.isRunning)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pauseWorkout,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _finishSet,
                  icon: const Icon(Icons.check),
                  label: const Text('Finish set'),
                ),
              ),
            ],
          )
        else if (session.hasStartedCurrentWorkout)
          FilledButton.icon(
            onPressed: _startWorkout,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Resume'),
          )
        else
          FilledButton.icon(
            onPressed: _startWorkout,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start'),
          ),
        ..._buildCompletedList(),
      ],
    );
  }

  Widget _buildRestView(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);
    final betweenWorkouts = session.restIsBetweenWorkouts;
    final workout = session.currentWorkout;
    final totalMs = session.restTotalSeconds * 1000;
    final progress = totalMs == 0
        ? 0.0
        : (session.restRemaining.inMilliseconds / totalMs)
              .clamp(0.0, 1.0)
              .toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          betweenWorkouts
              ? 'Rest before your next workout'
              : 'Rest before set ${session.currentSetNumber} of '
                    '${workout?.sets ?? 0}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 20),
        Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: progress),
                    duration: const Duration(milliseconds: 1000),
                    builder: (context, value, _) => CircularProgressIndicator(
                      value: value,
                      strokeWidth: 10,
                      strokeCap: StrokeCap.round,
                      color: theme.colorScheme.tertiary,
                      backgroundColor: theme.colorScheme.onTertiaryContainer
                          .withValues(alpha: 0.15),
                    ),
                  ),
                ),
                Text(
                  _formatDuration(session.restRemaining),
                  style: _timerStyle(context),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (betweenWorkouts)
          Text(
            'You\'ll choose what\'s next when the timer ends',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          )
        else if (workout != null) ...[
          Text(
            workout.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _WorkoutStats(workout, alignment: WrapAlignment.center),
        ],
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: _skipRest,
          icon: const Icon(Icons.skip_next),
          label: const Text('Skip rest'),
        ),
        if (betweenWorkouts) ..._buildCompletedList(),
      ],
    );
  }

  Widget _buildPickNextView(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose your next workout',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        ...session.remainingWorkouts.map(
          (workout) => Card(
            elevation: 0,
            color: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
              title: Text(
                workout.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _WorkoutStats(workout),
              ),
              trailing: Icon(
                Icons.play_circle_fill,
                size: 32,
                color: scheme.primary,
              ),
              onTap: () => _chooseWorkout(workout),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _endEarly, child: const Text('End workout')),
        ..._buildCompletedList(),
      ],
    );
  }

  Widget _buildCompletionSummary(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.emoji_events_outlined,
          size: 56,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 8),
        Text(
          'Workout complete',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'Total ${_formatDuration(session.totalDuration)}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall,
        ),
        ..._buildCompletedList(),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            await widget.onFinish();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _WorkoutEditorDialog extends StatefulWidget {
  const _WorkoutEditorDialog({required this.categories, this.entry});

  final WorkoutEntry? entry;
  final List<String> categories;

  @override
  State<_WorkoutEditorDialog> createState() => _WorkoutEditorDialogState();
}

class _WorkoutEditorDialogState extends State<_WorkoutEditorDialog> {
  static const _newCategoryValue = '__new_category__';

  late final TextEditingController _nameController;
  late final TextEditingController _newCategoryController;
  late final TextEditingController _setsController;
  late final TextEditingController _repsController;
  late final TextEditingController _weightController;
  late String _selectedCategory;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _nameController = TextEditingController(text: entry?.name);
    _newCategoryController = TextEditingController();
    _selectedCategory =
        entry != null && widget.categories.contains(entry.category)
        ? entry.category
        : _newCategoryValue;
    _setsController = TextEditingController(text: entry?.sets.toString());
    _repsController = TextEditingController(text: entry?.reps.toString());
    _weightController = TextEditingController(
      text: entry == null ? '' : _formatWeight(entry.minimumWeight),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _newCategoryController.dispose();
    _setsController.dispose();
    _repsController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      WorkoutDraft(
        name: _nameController.text.trim(),
        category: _selectedCategory == _newCategoryValue
            ? _newCategoryController.text.trim()
            : _selectedCategory,
        sets: int.parse(_setsController.text),
        reps: int.parse(_repsController.text),
        minimumWeight: double.parse(_weightController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.entry != null;
    return ModuleBottomSheet(
      title: isEditing ? 'Edit workout' : 'Add workout',
      actions: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Workout name'),
              textCapitalization: TextCapitalization.sentences,
              validator: _requiredValidator,
            ),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                ...widget.categories.map(
                  (category) =>
                      DropdownMenuItem(value: category, child: Text(category)),
                ),
                const DropdownMenuItem(
                  value: _newCategoryValue,
                  child: Text('Create new category'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedCategory = value);
                }
              },
              validator: (value) => value == null ? 'Required' : null,
            ),
            if (_selectedCategory == _newCategoryValue)
              TextFormField(
                controller: _newCategoryController,
                decoration: const InputDecoration(
                  labelText: 'New category name',
                  hintText: 'Core and Conditioning',
                ),
                textCapitalization: TextCapitalization.words,
                validator: _requiredValidator,
              ),
            TextFormField(
              controller: _setsController,
              decoration: const InputDecoration(labelText: 'Sets'),
              keyboardType: TextInputType.number,
              validator: _positiveIntegerValidator,
            ),
            TextFormField(
              controller: _repsController,
              decoration: const InputDecoration(labelText: 'Reps'),
              keyboardType: TextInputType.number,
              validator: _positiveIntegerValidator,
            ),
            TextFormField(
              controller: _weightController,
              decoration: const InputDecoration(
                labelText: 'Minimum weight',
                suffixText: 'lb',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: _weightValidator,
            ),
          ],
        ),
      ),
    );
  }
}

String? _requiredValidator(String? value) {
  if (value == null || value.trim().isEmpty) return 'Required';
  return null;
}

String? _positiveIntegerValidator(String? value) {
  final number = int.tryParse(value ?? '');
  if (number == null || number <= 0) {
    return 'Enter a whole number greater than 0';
  }
  return null;
}

String? _weightValidator(String? value) {
  final number = double.tryParse(value ?? '');
  if (number == null || number < 0) return 'Enter 0 or more';
  return null;
}

String _formatWeight(double weight) {
  return weight == weight.roundToDouble()
      ? weight.toStringAsFixed(0)
      : weight.toString();
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}