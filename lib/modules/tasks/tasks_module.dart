import 'package:flutter/material.dart';
import '../../shared/anchor_module.dart';


class _TaskEntry {
  _TaskEntry({
    required this.title,
    required this.notes,
    required this.isReminder,
    this.dueAt,
    this.isComplete = false,
  });

  String title;
  String notes;
  bool isReminder;
  DateTime? dueAt;
  bool isComplete;
}

class _TaskDraft {
  const _TaskDraft({
    required this.title,
    required this.notes,
    required this.isReminder,
    this.dueAt,
  });

  final String title;
  final String notes;
  final bool isReminder;
  final DateTime? dueAt;
}

class TasksModule implements AnchorModule {
  final List<_TaskEntry> _entries = [];
  final ValueNotifier<int> _revision = ValueNotifier(0);

  @override
  String get id => 'tasks';

  @override
  String get displayName => 'Tasks';

  @override
  Widget buildSummaryCard(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _revision,
      builder: (context, revision, child) {
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

  void _addEntry(_TaskDraft draft) {
    _entries.add(
      _TaskEntry(
        title: draft.title,
        notes: draft.notes,
        isReminder: draft.isReminder,
        dueAt: draft.dueAt,
      ),
    );
    _notifyChanged();
  }

  void _updateEntry(_TaskEntry entry, _TaskDraft draft) {
    entry
      ..title = draft.title
      ..notes = draft.notes
      ..isReminder = draft.isReminder
      ..dueAt = draft.dueAt;
    _notifyChanged();
  }

  void _deleteEntry(_TaskEntry entry) {
    _entries.remove(entry);
    _notifyChanged();
  }
}

class _TasksDetailView extends StatefulWidget {
  const _TasksDetailView({required this.module});

  final TasksModule module;

  @override
  State<_TasksDetailView> createState() => _TasksDetailViewState();
}

class _TasksDetailViewState extends State<_TasksDetailView> {
  Future<void> _createEntry() async {
    final draft = await showDialog<_TaskDraft>(
      context: context,
      builder: (context) => const _TaskEditorDialog(),
    );
    if (draft != null) {
      widget.module._addEntry(draft);
      setState(() {});
    }
  }

  Future<void> _editEntry(_TaskEntry entry) async {
    final draft = await showDialog<_TaskDraft>(
      context: context,
      builder: (context) => _TaskEditorDialog(entry: entry),
    );
    if (draft != null) {
      widget.module._updateEntry(entry, draft);
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
      widget.module._deleteEntry(entry);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.module._entries;
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks & Reminders')),
      body: entries.isEmpty
          ? const _EmptyTasksState()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: entries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Card(
                  child: ListTile(
                    onTap: () => _editEntry(entry),
                    leading: Checkbox(
                      value: entry.isComplete,
                      onChanged: (value) {
                        setState(() {
                          entry.isComplete = value ?? false;
                        });
                        widget.module._notifyChanged();
                      },
                    ),
                    title: Text(
                      entry.title,
                      style: TextStyle(
                        decoration: entry.isComplete
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    subtitle: _EntrySubtitle(entry: entry),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        if (action == 'edit') {
                          _editEntry(entry);
                        } else {
                          _removeEntry(entry);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createEntry,
        icon: const Icon(Icons.add),
        label: const Text('Add Task/Reminder'),
      ),
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

class _EntrySubtitle extends StatelessWidget {
  const _EntrySubtitle({required this.entry});

  final _TaskEntry entry;

  @override
  Widget build(BuildContext context) {
    final details = <String>[];
    if (entry.isReminder) {
      details.add('Reminder');
    }
    if (entry.dueAt != null) {
      final localizations = MaterialLocalizations.of(context);
      final date = localizations.formatMediumDate(entry.dueAt!);
      final time = localizations.formatTimeOfDay(
        TimeOfDay.fromDateTime(entry.dueAt!),
      );
      details.add('$date at $time');
    }
    if (entry.notes.isNotEmpty) {
      details.add(entry.notes);
    }
    return Text(details.isEmpty ? 'Task' : details.join(' · '));
  }
}

class _TaskEditorDialog extends StatefulWidget {
  const _TaskEditorDialog({this.entry});

  final _TaskEntry? entry;

  @override
  State<_TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends State<_TaskEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late bool _isReminder;
  DateTime? _dueAt;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.entry?.title);
    _notesController = TextEditingController(text: widget.entry?.notes);
    _isReminder = widget.entry?.isReminder ?? false;
    _dueAt = widget.entry?.dueAt;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDueAt() async {
    final now = DateTime.now();
    final selectedDate = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
      initialDate: _dueAt != null && !_dueAt!.isBefore(now)
          ? _dueAt!
          : now,
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
        dueAt: _isReminder ? _dueAt : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dueLabel = _dueAt == null
        ? 'Set date and time'
        : '${MaterialLocalizations.of(context).formatMediumDate(_dueAt!)} at '
            '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(_dueAt!))}';
    return AlertDialog(
      title: Text(widget.entry == null ? 'Add Task/Reminder' : 'Edit Task/Reminder'),
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
            if (_isReminder)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _pickDueAt,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(dueLabel),
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
