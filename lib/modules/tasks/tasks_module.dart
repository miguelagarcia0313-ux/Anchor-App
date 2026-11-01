import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/anchor_module.dart';
import '../../shared/user_cloud_sync.dart';
import 'task_date_parser.dart';

bool _isDateOnlyDueAt(DateTime date) =>
    date.hour == 23 &&
    date.minute == 59 &&
    date.second == 0 &&
    date.millisecond == 0 &&
    date.microsecond == 0;
String _medicationDoseTaskId(String medicationId, DateTime dueAt) =>
    '$medicationId:${dueAt.toIso8601String()}';

enum _TaskLabelColor { blue, green, red, yellow, purple }

extension on _TaskLabelColor {
  Color get value => switch (this) {
    _TaskLabelColor.blue => Colors.blue,
    _TaskLabelColor.green => Colors.green,
    _TaskLabelColor.red => Colors.red,
    _TaskLabelColor.yellow => Colors.yellow,
    _TaskLabelColor.purple => Colors.purple,
  };
}

class _TaskLabel {
  const _TaskLabel({required this.id, required this.name, required this.color});

  final String id;
  final String name;
  final _TaskLabelColor color;

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'color': color.name};

  factory _TaskLabel.fromMap(Map<String, dynamic> map) {
    return _TaskLabel(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      color: _TaskLabelColor.values.firstWhere(
        (color) => color.name == map['color'],
        orElse: () => _TaskLabelColor.blue,
      ),
    );
  }
}

const _reminderLeadTimeLabels = <int, String>{
  5: '5 minutes before',
  10: '10 minutes before',
  15: '15 minutes before',
  30: '30 minutes before',
  60: '1 hour before',
  120: '2 hours before',
  1440: '1 day before',
  10080: '1 week before',
};

class _TaskEntry {
  _TaskEntry({
    required this.id,
    required this.title,
    required this.notes,
    required this.isReminder,
    this.medicationId,
    this.medicationName,
    this.dueAt,
    this.reminderMinutesBefore,
    this.labelId,
    this.isComplete = false,
  });

  final String id;
  String title;
  String notes;
  bool isReminder;
  String? medicationId;
  String? medicationName;
  DateTime? dueAt;
  int? reminderMinutesBefore;
  String? labelId;
  bool isComplete;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'notes': notes,
      'isReminder': isReminder,
      'medicationId': medicationId,
      'medicationName': medicationName,
      'dueAt': dueAt?.toIso8601String(),
      'reminderMinutesBefore': reminderMinutesBefore,
      'labelId': labelId,
      'isComplete': isComplete,
    };
  }

  factory _TaskEntry.fromMap(Map<String, dynamic> map) {
    return _TaskEntry(
      id:
          map['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: map['title'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      isReminder: map['isReminder'] as bool? ?? false,
      medicationId: map['medicationId'] as String?,
      medicationName: map['medicationName'] as String?,
      dueAt: map['dueAt'] == null
          ? null
          : DateTime.tryParse(map['dueAt'] as String),
      reminderMinutesBefore: map['reminderMinutesBefore'] as int?,
      labelId: map['labelId'] as String?,
      isComplete: map['isComplete'] as bool? ?? false,
    );
  }
}

class _TaskDraft {
  const _TaskDraft({
    required this.title,
    required this.notes,
    required this.isReminder,
    this.dueAt,
    this.reminderMinutesBefore,
    this.labelId,
  });

  final String title;
  final String notes;
  final bool isReminder;
  final DateTime? dueAt;
  final int? reminderMinutesBefore;
  final String? labelId;
}

enum _TaskFilter { all, today, upcoming, overdue, noDueDate, completed }

enum _TaskSort { dueSoonest, dueLatest, title, label }

class TasksModule implements AnchorModule {
  TasksModule({String? userId})
    : _userIdOverride = userId,
      _cloud = UserCloudSync.forCurrentUser(userIdOverride: userId);

  static const _legacyStorageKey = 'tasks.entries';
  static const _legacyMigrationKey = 'tasks.userScopedMigrationComplete';

  final String? _userIdOverride;

  late final String userId =
      _userIdOverride ??
      (Firebase.apps.isEmpty
          ? 'local'
          : FirebaseAuth.instance.currentUser?.uid ?? 'local');
  String get _storageKey => 'tasks.$userId.entries';

  final List<_TaskEntry> _entries = [];
  final ValueNotifier<int> _revision = ValueNotifier(0);
  final UserCloudSync? _cloud;
  late final Future<void> _ready = _loadEntries();

  @override
  String get id => 'tasks';

  @override
  String get displayName => 'Tasks';

  Future<void> get ready => _ready;

  @override
  Widget buildSummaryCard(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _revision,
      builder: (context, revision, child) {
        if (_entries.isEmpty && _revision.value == 0) {
          return const Card(
            child: ListTile(
              leading: Icon(Icons.check_circle_outline),
              title: Text('Tasks & Reminders'),
              subtitle: Text('Loading tasks...'),
              trailing: Icon(Icons.chevron_right),
            ),
          );
        }
        final openCount = _entries.where((entry) => !entry.isComplete).length;
        final reminderCount = _entries
            .where((entry) => entry.isReminder && !entry.isComplete)
            .length;
        final summary = _entries.isEmpty
            ? 'Add a task or reminder'
            : '$openCount open · $reminderCount reminders';

        return Card(
          child: ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: const Text('Tasks & Reminders'),
            subtitle: Text(summary),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }

  @override
  Widget buildDetailView(BuildContext context) {
    return _TasksDetailView(module: this);
  }

  void _notifyChanged() {
    _revision.value++;
  }

  Future<void> _addEntry(_TaskDraft draft) async {
    final entry = _TaskEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: draft.title,
      notes: draft.notes,
      isReminder: draft.isReminder,
      dueAt: draft.dueAt,
      reminderMinutesBefore: draft.reminderMinutesBefore,
      labelId: draft.labelId,
    );
    _entries.add(entry);
    _notifyChanged();
    await _persistEntries();
  }

  Future<void> _updateEntry(_TaskEntry entry, _TaskDraft draft) async {
    entry
      ..title = draft.title
      ..notes = draft.notes
      ..isReminder = draft.isReminder
      ..dueAt = draft.dueAt
      ..reminderMinutesBefore = draft.reminderMinutesBefore
      ..labelId = draft.labelId;
    _notifyChanged();
    await _persistEntries();
  }

  String get _labelsStorageKey => 'tasks.$userId.labels';
  final List<_TaskLabel> _labels = [];

  Future<void> _addLabel(String name, _TaskLabelColor color) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty ||
        _labels.any(
          (label) => label.name.toLowerCase() == normalizedName.toLowerCase(),
        )) {
      return;
    }
    _labels.add(
      _TaskLabel(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: normalizedName,
        color: color,
      ),
    );
    _notifyChanged();
    await _persistLabels();
  }

  _TaskLabel? _labelFor(String? id) {
    if (id == null) return null;
    for (final label in _labels) {
      if (label.id == id) return label;
    }
    return null;
  }

  Future<void> _deleteEntry(_TaskEntry entry) async {
    _entries.remove(entry);
    _notifyChanged();
    await _persistEntries();
  }

  Future<void> syncMedicationDoseReminders({
    required String medicationId,
    required String medicationName,
    required int firstDoseHour,
    required int firstDoseMinute,
    required int intervalHours,
  }) async {
    if (intervalHours < 1 || intervalHours > 24) return;
    await _ready;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final horizon = now.add(const Duration(days: 1));
    var doseAt = DateTime(
      today.year,
      today.month,
      today.day,
      firstDoseHour,
      firstDoseMinute,
    );
    while (doseAt.isBefore(now)) {
      doseAt = doseAt.add(Duration(hours: intervalHours));
    }
    final doses = <DateTime>[];
    while (doseAt.isBefore(horizon)) {
      doses.add(doseAt);
      doseAt = doseAt.add(Duration(hours: intervalHours));
    }

    final expectedIds = doses
        .map((dose) => _medicationDoseTaskId(medicationId, dose))
        .toSet();
    final countBeforeRemoval = _entries.length;
    _entries.removeWhere((entry) {
      return entry.medicationId == medicationId &&
          !entry.isComplete &&
          !expectedIds.contains(entry.id);
    });
    var changed = _entries.length != countBeforeRemoval;

    for (var index = 0; index < doses.length; index++) {
      final dose = doses[index];
      final id = _medicationDoseTaskId(medicationId, dose);
      if (_entries.any((entry) => entry.id == id)) continue;
      _entries.add(
        _TaskEntry(
          id: id,
          title: 'Take $medicationName - Dose ${index + 1}',
          notes: 'Dose ${index + 1} of ${doses.length}',
          isReminder: true,
          medicationId: medicationId,
          medicationName: medicationName,
          dueAt: dose,
        ),
      );
      changed = true;
    }

    if (changed) {
      _notifyChanged();
      await _persistEntries();
    }
  }

  Future<void> removeMedicationDoseReminders(String medicationId) async {
    await _ready;
    final countBeforeRemoval = _entries.length;
    _entries.removeWhere((entry) => entry.medicationId == medicationId);
    if (_entries.length != countBeforeRemoval) {
      _notifyChanged();
      await _persistEntries();
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
          (encodedEntry) => _TaskEntry.fromMap(
            jsonDecode(encodedEntry) as Map<String, dynamic>,
          ),
        ),
      );
    final storedLabels = preferences.getStringList(_labelsStorageKey) ?? [];
    _labels
      ..clear()
      ..addAll(
        storedLabels.map(
          (encodedLabel) => _TaskLabel.fromMap(
            jsonDecode(encodedLabel) as Map<String, dynamic>,
          ),
        ),
      );
    _notifyChanged();
    final cloud = _cloud;
    if (cloud == null) return;
    await cloud.migrateLocalDataOnce('tasks', () async {
      await cloud.setRecords(
        'tasks',
        'entries',
        _entries.map((entry) => MapEntry(entry.id, entry.toMap())),
      );
    });
    await cloud.migrateLocalDataOnce('tasks_labels', () async {
      await cloud.setRecords(
        'tasks',
        'labels',
        _labels.map((label) => MapEntry(label.id, label.toMap())),
      );
    });
    cloud
        .records('tasks', 'entries')
        .snapshots()
        .listen(
          (snapshot) {
            _entries
              ..clear()
              ..addAll(
                snapshot.docs.map((document) {
                  return _TaskEntry.fromMap(document.data());
                }),
              );
            _notifyChanged();
            unawaited(_persistEntriesLocally());
          },
          onError: (Object error, StackTrace stackTrace) {
            cloud.reportStreamError('tasks', error, stackTrace);
          },
        );
    cloud
        .records('tasks', 'labels')
        .snapshots()
        .listen(
          (snapshot) {
            _labels
              ..clear()
              ..addAll(
                snapshot.docs.map(
                  (document) => _TaskLabel.fromMap(document.data()),
                ),
              );
            _notifyChanged();
            unawaited(_persistLabelsLocally());
          },
          onError: (Object error, StackTrace stackTrace) {
            cloud.reportStreamError('tasks', error, stackTrace);
          },
        );
  }

  Future<void> _persistEntries() async {
    await _persistEntriesLocally();
    await _cloud?.replaceRecords(
      'tasks',
      'entries',
      _entries.map((entry) => MapEntry(entry.id, entry.toMap())),
    );
  }

  Future<void> _persistEntriesLocally() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _storageKey,
      _entries.map((entry) => jsonEncode(entry.toMap())).toList(),
    );
  }

  Future<void> _persistLabels() async {
    await _persistLabelsLocally();
    await _cloud?.replaceRecords(
      'tasks',
      'labels',
      _labels.map((label) => MapEntry(label.id, label.toMap())),
    );
  }

  Future<void> _persistLabelsLocally() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _labelsStorageKey,
      _labels.map((label) => jsonEncode(label.toMap())).toList(),
    );
  }
}

class _TasksDetailView extends StatefulWidget {
  const _TasksDetailView({required this.module});

  final TasksModule module;

  @override
  State<_TasksDetailView> createState() => _TasksDetailViewState();
}

class _TasksDetailViewState extends State<_TasksDetailView> {
  _TaskFilter _filter = _TaskFilter.all;
  _TaskSort _sort = _TaskSort.dueSoonest;
  String? _labelFilterId;

  @override
  void initState() {
    super.initState();
    widget.module._revision.addListener(_handleModuleChanged);
  }

  @override
  void dispose() {
    widget.module._revision.removeListener(_handleModuleChanged);
    super.dispose();
  }

  void _handleModuleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _createEntry() async {
    final draft = await showDialog<_TaskDraft>(
      context: context,
      builder: (context) => _TaskEditorDialog(labels: widget.module._labels),
    );
    if (draft != null) {
      await widget.module._addEntry(draft);
      setState(() {});
    }
  }

  Future<void> _editEntry(_TaskEntry entry) async {
    final draft = await showDialog<_TaskDraft>(
      context: context,
      builder: (context) =>
          _TaskEditorDialog(entry: entry, labels: widget.module._labels),
    );
    if (draft != null) {
      await widget.module._updateEntry(entry, draft);
      setState(() {});
    }
  }

  Future<void> _removeEntry(_TaskEntry entry) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Remove "${entry.title}" from Tasks & Reminders?'),
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
      await widget.module._deleteEntry(entry);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: widget.module.ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final entries = widget.module._entries;
        if (entries.isEmpty) {
          return Scaffold(
            appBar: _buildAppBar(),
            body: const _EmptyTasksState(),
            floatingActionButton: _AddTaskButton(onPressed: _createEntry),
          );
        }

        final filteredEntries = _filteredEntries(entries);
        return Scaffold(
          appBar: _buildAppBar(),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: [
                _buildControls(),
                const SizedBox(height: 12),
                Expanded(
                  child: filteredEntries.isEmpty
                      ? _NoMatchingTasksState(
                          filter: _filter,
                          hasLabelFilter: _labelFilterId != null,
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount: filteredEntries.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final entry = filteredEntries[index];
                            final isOverdue =
                                !entry.isComplete &&
                                entry.dueAt?.isBefore(DateTime.now()) == true;
                            final isOverdueReminder =
                                entry.isReminder && isOverdue;
                            return Card(
                              child: ListTile(
                                onTap: () => _editEntry(entry),
                                leading: Checkbox(
                                  value: entry.isComplete,
                                  onChanged: (value) async {
                                    setState(() {
                                      entry.isComplete = value ?? false;
                                    });
                                    widget.module._notifyChanged();
                                    await widget.module._persistEntries();
                                  },
                                ),
                                title: Text(
                                  isOverdue
                                      ? '${entry.title} - OVERDUE'
                                      : entry.title,
                                  style: TextStyle(
                                    color: isOverdueReminder
                                        ? Theme.of(context).colorScheme.error
                                        : null,
                                    decoration: entry.isComplete
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                subtitle: _EntrySubtitle(
                                  entry: entry,
                                  label: widget.module._labelFor(entry.labelId),
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (action) {
                                    if (action == 'edit') {
                                      _editEntry(entry);
                                    } else {
                                      _removeEntry(entry);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          floatingActionButton: _AddTaskButton(onPressed: _createEntry),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Tasks & Reminders'),
      actions: [
        IconButton(
          key: const Key('tasks_create_label_button'),
          tooltip: 'Create label',
          onPressed: _createLabel,
          icon: const Icon(Icons.label_outline),
        ),
      ],
    );
  }

  Future<void> _createLabel() async {
    final result = await showDialog<({String name, _TaskLabelColor color})>(
      context: context,
      builder: (context) => const _TaskLabelEditorDialog(),
    );
    if (result == null) return;
    if (!mounted) return;
    final duplicate = widget.module._labels.any(
      (label) => label.name.toLowerCase() == result.name.toLowerCase(),
    );
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A label with that name already exists.')),
      );
      return;
    }
    await widget.module._addLabel(result.name, result.color);
    if (mounted) setState(() {});
  }

  Widget _buildControls() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<_TaskFilter>(
                key: const Key('tasks_filter_dropdown'),
                initialValue: _filter,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Filter',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12),
                ),
                items: _TaskFilter.values
                    .map(
                      (filter) => DropdownMenuItem(
                        value: filter,
                        child: Text(_filterLabel(filter)),
                      ),
                    )
                    .toList(),
                onChanged: (filter) {
                  if (filter != null) {
                    setState(() => _filter = filter);
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<_TaskSort>(
                key: const Key('tasks_sort_dropdown'),
                initialValue: _sort,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Sort by',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12),
                ),
                items: _TaskSort.values
                    .map(
                      (sort) => DropdownMenuItem(
                        value: sort,
                        child: Text(_sortLabel(sort)),
                      ),
                    )
                    .toList(),
                onChanged: (sort) {
                  if (sort != null) {
                    setState(() => _sort = sort);
                  }
                },
              ),
            ),
          ],
        ),
        if (widget.module._labels.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            key: const Key('tasks_label_filter_dropdown'),
            initialValue: _labelFilterId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Filter by label',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All labels'),
              ),
              ...widget.module._labels.map(
                (label) => DropdownMenuItem<String?>(
                  value: label.id,
                  child: Text(label.name),
                ),
              ),
            ],
            onChanged: (labelId) => setState(() => _labelFilterId = labelId),
          ),
        ],
      ],
    );
  }

  List<_TaskEntry> _filteredEntries(List<_TaskEntry> entries) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final matchingEntries = entries.where((entry) {
      if (_labelFilterId != null && entry.labelId != _labelFilterId) {
        return false;
      }
      final dueAt = entry.dueAt;
      switch (_filter) {
        case _TaskFilter.all:
          return true;
        case _TaskFilter.today:
          return !entry.isComplete && dueAt != null && _isSameDay(dueAt, today);
        case _TaskFilter.upcoming:
          return !entry.isComplete &&
              dueAt != null &&
              _startOfDay(dueAt).isAfter(today);
        case _TaskFilter.overdue:
          return !entry.isComplete && dueAt != null && dueAt.isBefore(now);
        case _TaskFilter.noDueDate:
          return !entry.isComplete && dueAt == null;
        case _TaskFilter.completed:
          return entry.isComplete;
      }
    }).toList();

    final originalPositions = {
      for (var index = 0; index < entries.length; index++)
        entries[index]: index,
    };
    matchingEntries.sort((a, b) {
      final comparison = switch (_sort) {
        _TaskSort.dueSoonest => _compareDueDates(a.dueAt, b.dueAt),
        _TaskSort.dueLatest => _compareDueDates(
          a.dueAt,
          b.dueAt,
          descending: true,
        ),
        _TaskSort.title => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
        _TaskSort.label => _compareLabels(a.labelId, b.labelId),
      };
      return comparison != 0
          ? comparison
          : originalPositions[a]!.compareTo(originalPositions[b]!);
    });
    return matchingEntries;
  }

  static int _compareDueDates(
    DateTime? a,
    DateTime? b, {
    bool descending = false,
  }) {
    if (a == null) {
      return b == null ? 0 : 1;
    }
    if (b == null) {
      return -1;
    }
    final comparison = a.compareTo(b);
    return descending ? -comparison : comparison;
  }

  int _compareLabels(String? a, String? b) {
    final labelA = widget.module._labelFor(a)?.name;
    final labelB = widget.module._labelFor(b)?.name;
    if (labelA == null) return labelB == null ? 0 : 1;
    if (labelB == null) return -1;
    return labelA.toLowerCase().compareTo(labelB.toLowerCase());
  }

  static DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _filterLabel(_TaskFilter filter) => switch (filter) {
    _TaskFilter.all => 'All',
    _TaskFilter.today => 'Today',
    _TaskFilter.upcoming => 'Upcoming',
    _TaskFilter.overdue => 'Overdue',
    _TaskFilter.noDueDate => 'No due date',
    _TaskFilter.completed => 'Completed',
  };

  static String _sortLabel(_TaskSort sort) => switch (sort) {
    _TaskSort.dueSoonest => 'Soonest due',
    _TaskSort.dueLatest => 'Latest due',
    _TaskSort.title => 'Title A–Z',
    _TaskSort.label => 'Label A–Z',
  };
}

class _AddTaskButton extends StatelessWidget {
  const _AddTaskButton({this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onPressed,
      icon: const Icon(Icons.add),
      label: const Text('Add Task/Reminder'),
    );
  }
}

class _EmptyTasksState extends StatelessWidget {
  const _EmptyTasksState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.checklist_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No tasks or reminders yet!',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('Add a task or reminder to get started.'),
          ],
        ),
      ),
    );
  }
}

class _NoMatchingTasksState extends StatelessWidget {
  const _NoMatchingTasksState({
    required this.filter,
    required this.hasLabelFilter,
  });

  final _TaskFilter filter;
  final bool hasLabelFilter;

  @override
  Widget build(BuildContext context) {
    final message = switch (filter) {
      _TaskFilter.all => 'No tasks or reminders yet!',
      _TaskFilter.today => 'No tasks due today.',
      _TaskFilter.upcoming => 'No upcoming tasks.',
      _TaskFilter.overdue => 'No overdue tasks.',
      _TaskFilter.noDueDate => 'No tasks without a due date.',
      _TaskFilter.completed => 'No completed tasks.',
    };
    return Center(
      child: Text(hasLabelFilter ? 'No tasks match this label.' : message),
    );
  }
}

class _EntrySubtitle extends StatelessWidget {
  const _EntrySubtitle({required this.entry, this.label});

  final _TaskEntry entry;
  final _TaskLabel? label;

  @override
  Widget build(BuildContext context) {
    final details = <String>[];
    if (entry.isReminder) {
      details.add('Reminder');
    }
    if (entry.medicationName != null) {
      details.add('Medication: ${entry.medicationName}');
    }
    final reminderLeadTime = entry.reminderMinutesBefore;
    if (reminderLeadTime != null) {
      final label = _reminderLeadTimeLabels[reminderLeadTime];
      if (label != null) {
        details.add('Notification: $label');
      }
    }
    if (entry.dueAt != null) {
      final localizations = MaterialLocalizations.of(context);
      final date = localizations.formatMediumDate(entry.dueAt!);
      if (_isDateOnlyDueAt(entry.dueAt!)) {
        details.add(date);
      } else {
        final time = localizations.formatTimeOfDay(
          TimeOfDay.fromDateTime(entry.dueAt!),
        );
        details.add('$date at $time');
      }
    }
    if (entry.notes.isNotEmpty) {
      details.add(entry.notes);
    }
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(details.isEmpty ? 'Task' : details.join(' · ')),
        if (label != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: label!.color.value.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label!.name,
              style: TextStyle(
                color: label!.color.value,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _TaskLabelEditorDialog extends StatefulWidget {
  const _TaskLabelEditorDialog();

  @override
  State<_TaskLabelEditorDialog> createState() => _TaskLabelEditorDialogState();
}

class _TaskLabelEditorDialogState extends State<_TaskLabelEditorDialog> {
  final TextEditingController _nameController = TextEditingController();
  _TaskLabelColor _color = _TaskLabelColor.blue;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, (name: name, color: _color));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create label'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('task_label_name_field'),
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Label name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<_TaskLabelColor>(
            key: const Key('task_label_color_dropdown'),
            initialValue: _color,
            decoration: const InputDecoration(
              labelText: 'Color',
              border: OutlineInputBorder(),
            ),
            items: _TaskLabelColor.values
                .map(
                  (color) => DropdownMenuItem(
                    value: color,
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 16, color: color.value),
                        const SizedBox(width: 8),
                        Text(
                          color.name[0].toUpperCase() + color.name.substring(1),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
            onChanged: (color) {
              if (color != null) setState(() => _color = color);
            },
          ),
        ],
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

class _TaskEditorDialog extends StatefulWidget {
  const _TaskEditorDialog({this.entry, required this.labels});

  final _TaskEntry? entry;
  final List<_TaskLabel> labels;

  @override
  State<_TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends State<_TaskEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late bool _isReminder;
  DateTime? _dueAt;
  int? _reminderMinutesBefore;
  String? _labelId;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.entry?.title);
    _notesController = TextEditingController(text: widget.entry?.notes);
    _isReminder = widget.entry?.isReminder ?? false;
    _dueAt = widget.entry?.dueAt;
    _reminderMinutesBefore = widget.entry?.reminderMinutesBefore;
    _labelId = widget.entry?.labelId;
    _titleController.addListener(_updateDueAtFromText);
    _notesController.addListener(_updateDueAtFromText);
  }

  @override
  void dispose() {
    _titleController.removeListener(_updateDueAtFromText);
    _notesController.removeListener(_updateDueAtFromText);
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _updateDueAtFromText() {
    final text = '${_titleController.text} ${_notesController.text}';
    final parsedDueAt = parseTaskDateTime(text);
    final hasTime = containsTaskTime(text);
    if (parsedDueAt != null &&
        (parsedDueAt != _dueAt || (hasTime && !_isReminder)) &&
        mounted) {
      setState(() {
        _dueAt = parsedDueAt;
        if (hasTime) {
          _isReminder = true;
        }
      });
    }
  }

  Future<void> _pickDueAt() async {
    final now = DateTime.now();
    final selectedDate = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
      initialDate: _dueAt != null && !_dueAt!.isBefore(now) ? _dueAt! : now,
    );
    if (selectedDate == null || !mounted) {
      return;
    }
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: _dueAt != null
          ? TimeOfDay.fromDateTime(_dueAt!)
          : TimeOfDay.fromDateTime(now),
    );
    if (selectedTime == null || !mounted) {
      return;
    }
    setState(() {
      _dueAt = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      return;
    }
    Navigator.pop(
      context,
      _TaskDraft(
        title: title,
        notes: _notesController.text.trim(),
        isReminder: _isReminder,
        dueAt: _dueAt,
        reminderMinutesBefore: _reminderMinutesBefore,
        labelId: _labelId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dueLabel = _dueAt == null
        ? 'Set due date and time'
        : _isDateOnlyDueAt(_dueAt!)
        ? MaterialLocalizations.of(context).formatMediumDate(_dueAt!)
        : '${MaterialLocalizations.of(context).formatMediumDate(_dueAt!)} at '
              '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(_dueAt!))}';
    return AlertDialog(
      title: Text(
        widget.entry == null ? 'Add Task/Reminder' : 'Edit Task/Reminder',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Task/Reminder',
                hintText: 'e.g. Reminder to call the dentist',
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Extra Details',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: const Key('task_label_dropdown'),
              initialValue: _labelId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Label',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('No label'),
                ),
                ...widget.labels.map(
                  (label) => DropdownMenuItem<String?>(
                    value: label.id,
                    child: Text(label.name),
                  ),
                ),
              ],
              onChanged: (labelId) => setState(() => _labelId = labelId),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Set tasks as Reminder'),
              value: _isReminder,
              onChanged: (value) {
                setState(() {
                  _isReminder = value;
                });
              },
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _pickDueAt,
                icon: const Icon(Icons.event_outlined),
                label: Text(dueLabel),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              key: const Key('task_reminder_lead_time_dropdown'),
              initialValue: _reminderMinutesBefore,
              hint: const Text('No notification'),
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Notify before due',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('No notification'),
                ),
                ..._reminderLeadTimeLabels.entries.map(
                  (option) => DropdownMenuItem<int?>(
                    value: option.key,
                    child: Text(option.value),
                  ),
                ),
              ],
              onChanged: _dueAt == null
                  ? null
                  : (minutes) {
                      setState(() {
                        _reminderMinutesBefore = minutes;
                      });
                    },
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'This setting is saved for future notifications. '
                'Notifications are not sent yet.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
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
