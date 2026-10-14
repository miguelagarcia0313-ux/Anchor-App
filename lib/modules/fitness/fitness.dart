import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/anchor_module.dart';

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
  FitnessModule({required this.userId});

  static const _legacyStorageKey = 'fitness.workouts';
  static const _legacyMigrationKey = 'fitness.userScopedMigrationComplete';

  final String userId;

  String get _storageKey => 'fitness.$userId.workouts';
  String get _categoryDurationsKey => 'fitness.$userId.categoryDurations';

  final List<WorkoutEntry> _entries = [];
  final Map<String, Duration> _categoryDurations = {};
  final ValueNotifier<int> _revision = ValueNotifier(0);
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

  List<String> get categories =>
      _entries.map((entry) => entry.category).toSet().toList()..sort();

  Map<String, Duration> get categoryDurations =>
      Map.unmodifiable(_categoryDurations);

  void updateCategoryDuration(String category, Duration duration) {
    _categoryDurations[category] = duration;
  }

  Future<void> persistCategoryDurations() async {
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

  Future<void> addEntry(WorkoutDraft draft) async {
    _entries.add(
      WorkoutEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: draft.name,
        category: draft.category,
        sets: draft.sets,
        reps: draft.reps,
        minimumWeight: draft.minimumWeight,
      ),
    );
    _notifyChanged();
    await _persistEntries();
  }

  Future<void> updateEntry(WorkoutEntry entry, WorkoutDraft draft) async {
    entry
      ..name = draft.name
      ..category = draft.category
      ..sets = draft.sets
      ..reps = draft.reps
      ..minimumWeight = draft.minimumWeight;
    _notifyChanged();
    await _persistEntries();
  }

  Future<void> deleteEntry(WorkoutEntry entry) async {
    _entries.remove(entry);
    _notifyChanged();
    await _persistEntries();
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
  }

  Future<void> _persistEntries() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _storageKey,
      _entries.map((entry) => jsonEncode(entry.toMap())).toList(),
    );
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
  Timer? _sessionTicker;

  @override
  void initState() {
    super.initState();
    widget.module.ready.then((_) {
      if (mounted) {
        setState(() {
          _categoryDurations
            ..clear()
            ..addAll(widget.module.categoryDurations);
        });
      }
    });
  }

  @override
  void dispose() {
    _sessionTicker?.cancel();
    super.dispose();
  }

  Future<void> _addWorkout() async {
    final draft = await showDialog<WorkoutDraft>(
      context: context,
      builder: (context) =>
          _WorkoutEditorDialog(categories: widget.module.categories),
    );
    if (draft != null) {
      await widget.module.addEntry(draft);
      setState(() {});
    }
  }

  Future<void> _editWorkout(WorkoutEntry entry) async {
    final draft = await showDialog<WorkoutDraft>(
      context: context,
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

  Future<void> _deleteWorkout(WorkoutEntry entry) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete workout?'),
        content: Text('Remove "${entry.name}" from ${entry.category}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete == true) {
      await widget.module.deleteEntry(entry);
      setState(() {});
    }
  }

  Future<void> _startGuidedWorkout() async {
    final categories = widget.module.categories;
    var session = _activeSession;
    if (session != null) {
      final choice = await showDialog<_SessionReturnChoice>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Workout session saved'),
          content: Text(
            'Continue ${session!.category} where you left off, or reset and '
            'start a new workout timing?',
          ),
          actions: [
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
              onPressed: () =>
                  Navigator.pop(context, _SessionReturnChoice.continueSession),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == _SessionReturnChoice.reset) session = null;
    }

    if (session == null) {
      if (categories.isEmpty) return;
      final setup = await showDialog<_GuidedWorkoutSetup>(
        context: context,
        builder: (context) => _WorkoutSetupDialog(categories: categories),
      );
      if (setup == null || !mounted) return;

      final workouts = widget.module.entries
          .where((entry) => entry.category == setup.category)
          .toList();
      if (workouts.isEmpty) return;

      session = _GuidedWorkoutSession(
        category: setup.category,
        workouts: workouts,
        restMinutes: setup.restMinutes,
      );
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
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
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

  @override
  Widget build(BuildContext context) {
    final entriesByCategory = <String, List<WorkoutEntry>>{};
    for (final entry in widget.module.entries) {
      entriesByCategory.putIfAbsent(entry.category, () => []).add(entry);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Fitness')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: entriesByCategory.isEmpty ? null : _startGuidedWorkout,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play'),
            ),
          ),
          const SizedBox(height: 12),
          if (entriesByCategory.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No workouts logged yet.')),
            )
          else
            ...entriesByCategory.entries.map(
              (category) => _WorkoutCategorySection(
                category: category.key,
                sessionDuration: _categoryDurations[category.key],
                entries: category.value,
                onEdit: _editWorkout,
                onDelete: _deleteWorkout,
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addWorkout,
        icon: const Icon(Icons.add),
        label: const Text('Add workout'),
      ),
    );
  }
}

enum _SessionReturnChoice { continueSession, reset }

class _GuidedWorkoutSetup {
  const _GuidedWorkoutSetup({
    required this.category,
    required this.restMinutes,
  });

  final String category;
  final int restMinutes;
}

class _GuidedWorkoutSession {
  _GuidedWorkoutSession({
    required this.category,
    required this.workouts,
    required this.restMinutes,
  });

  final String category;
  final List<WorkoutEntry> workouts;
  final int restMinutes;
  final Stopwatch _stopwatch = Stopwatch();
  final Map<String, Duration> completedDurations = {};
  int workoutIndex = 0;
  bool _startedCurrentWorkout = false;
  DateTime? restEndsAt;

  bool get isComplete => workoutIndex >= workouts.length;
  bool get isRunning => _stopwatch.isRunning;
  bool get isResting => restEndsAt != null;
  bool get hasStartedCurrentWorkout => _startedCurrentWorkout;
  Duration get currentElapsed => _stopwatch.elapsed;

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

  void startOrResumeWorkout() {
    if (!_startedCurrentWorkout) {
      _stopwatch.reset();
      _startedCurrentWorkout = true;
    }
    _stopwatch.start();
  }

  void pauseWorkout() => _stopwatch.stop();

  void stopWorkout() {
    _stopwatch.stop();
    final workout = workouts[workoutIndex];
    completedDurations[workout.id] = _stopwatch.elapsed;
    _startedCurrentWorkout = false;

    if (workoutIndex < workouts.length - 1) {
      restEndsAt = DateTime.now().add(Duration(minutes: restMinutes));
    } else {
      workoutIndex++;
    }
  }

  bool advanceRestIfComplete() {
    final end = restEndsAt;
    if (end == null || DateTime.now().isBefore(end)) return false;
    restEndsAt = null;
    workoutIndex++;
    return true;
  }

  void skipRest() {
    if (restEndsAt == null) return;
    restEndsAt = null;
    workoutIndex++;
  }
}

class _WorkoutSetupDialog extends StatefulWidget {
  const _WorkoutSetupDialog({required this.categories});

  final List<String> categories;

  @override
  State<_WorkoutSetupDialog> createState() => _WorkoutSetupDialogState();
}

class _WorkoutSetupDialogState extends State<_WorkoutSetupDialog> {
  late String _category = widget.categories.first;
  int _restMinutes = 1;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Set up guided workout'),
    content: Column(
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
            if (category != null) setState(() => _category = category);
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          initialValue: _restMinutes,
          decoration: const InputDecoration(labelText: 'Rest between workouts'),
          items: List.generate(
            5,
            (index) => DropdownMenuItem(
              value: index + 1,
              child: Text('${index + 1} ${index == 0 ? 'minute' : 'minutes'}'),
            ),
          ),
          onChanged: (minutes) {
            if (minutes != null) setState(() => _restMinutes = minutes);
          },
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _GuidedWorkoutSetup(category: _category, restMinutes: _restMinutes),
        ),
        child: const Text('Start'),
      ),
    ],
  );
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

  @override
  void initState() {
    super.initState();
    widget.session.advanceRestIfComplete();
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

  bool get _isComplete => widget.session.isComplete;

  void _startWorkout() {
    widget.session.startOrResumeWorkout();
    _syncTicker();
    setState(() {});
    widget.onSessionChanged(true);
  }

  void _pauseWorkout() {
    widget.session.pauseWorkout();
    _syncTicker();
    setState(() {});
    widget.onSessionChanged(true);
  }

  void _stopWorkout() {
    widget.session.stopWorkout();
    _syncTicker();
    setState(() {});
    widget.onSessionChanged(true);
  }

  void _skipRest() {
    widget.session.skipRest();
    _syncTicker();
    setState(() {});
    widget.onSessionChanged(true);
  }

  void _syncTicker() {
    _ticker?.cancel();
    if (widget.session.isRunning || widget.session.isResting) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        widget.session.advanceRestIfComplete();
        setState(() {});
        widget.onSessionChanged(false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 48)
        .clamp(0.0, 440.0)
        .toDouble();
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.session.category,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close workout session',
                        onPressed: () {
                          widget.onSessionChanged(true);
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const Divider(),
                  if (_isComplete)
                    _buildCompletionSummary(context)
                  else if (widget.session.isResting)
                    _buildRestView(context)
                  else
                    _buildWorkoutView(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkoutView(BuildContext context) {
    final session = widget.session;
    final workout = session.workouts[session.workoutIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Workout ${session.workoutIndex + 1} of ${session.workouts.length}',
        ),
        const SizedBox(height: 16),
        Text(workout.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          '${workout.sets} sets x ${workout.reps} reps  |  '
          '${_formatWeight(workout.minimumWeight)} min weight',
        ),
        const SizedBox(height: 24),
        Text(
          _formatDuration(session.currentElapsed),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall,
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
                  onPressed: _stopWorkout,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ),
            ],
          )
        else if (session.hasStartedCurrentWorkout)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _startWorkout,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Resume'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _stopWorkout,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                ),
              ),
            ],
          )
        else
          FilledButton.icon(
            onPressed: _startWorkout,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start'),
          ),
        const SizedBox(height: 12),
        ...session.workouts.take(session.workoutIndex).map((completedWorkout) {
          final duration = session.completedDurations[completedWorkout.id];
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.check_circle_outline),
            title: Text(completedWorkout.name),
            trailing: Text(_formatDuration(duration ?? Duration.zero)),
          );
        }),
      ],
    );
  }

  Widget _buildRestView(BuildContext context) {
    final session = widget.session;
    final nextWorkout = session.workouts[session.workoutIndex + 1];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Rest before workout ${session.workoutIndex + 2}'),
        const SizedBox(height: 8),
        Text(
          _formatDuration(session.restRemaining),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 8),
        Text('Next: ${nextWorkout.name}', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: _skipRest, child: const Text('Skip rest')),
      ],
    );
  }

  Widget _buildCompletionSummary(BuildContext context) {
    final session = widget.session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Workout list complete',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        ...session.workouts.map(
          (workout) => ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.check_circle_outline),
            title: Text(workout.name),
            trailing: Text(
              _formatDuration(
                session.completedDurations[workout.id] ?? Duration.zero,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
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

class _WorkoutCategorySection extends StatelessWidget {
  const _WorkoutCategorySection({
    required this.category,
    required this.entries,
    required this.onEdit,
    required this.onDelete,
    this.sessionDuration,
  });

  final String category;
  final List<WorkoutEntry> entries;
  final ValueChanged<WorkoutEntry> onEdit;
  final ValueChanged<WorkoutEntry> onDelete;
  final Duration? sessionDuration;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            Expanded(child: Text(category)),
            if (sessionDuration != null) ...[
              const SizedBox(width: 8),
              Text(
                'Total ${_formatDuration(sessionDuration!)}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ],
        ),
        children: entries
            .map(
              (entry) => ListTile(
                title: Text(entry.name),
                subtitle: Text(
                  '${entry.sets} sets x ${entry.reps} reps  |  '
                  '${_formatWeight(entry.minimumWeight)} min weight',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'edit') {
                      onEdit(entry);
                    } else if (action == 'delete') {
                      onDelete(entry);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            )
            .toList(),
      ),
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
    return AlertDialog(
      title: Text(isEditing ? 'Edit workout' : 'Add workout'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
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
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    ),
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
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
