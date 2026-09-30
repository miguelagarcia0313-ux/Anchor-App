import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/anchor_module.dart';

class _WorkoutEntry {
  _WorkoutEntry({
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

  factory _WorkoutEntry.fromMap(Map<String, dynamic> map) {
    return _WorkoutEntry(
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
  static const _storageKey = 'fitness.workouts';

  final List<_WorkoutEntry> _entries = [];
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

  List<_WorkoutEntry> get entries => List.unmodifiable(_entries);

  List<String> get categories =>
      _entries.map((entry) => entry.category).toSet().toList()..sort();

  void addEntry(_WorkoutDraft draft) {
    _entries.add(
      _WorkoutEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: draft.name,
        category: draft.category,
        sets: draft.sets,
        reps: draft.reps,
        minimumWeight: draft.minimumWeight,
      ),
    );
    _notifyChanged();
    _persistEntries();
  }

  void updateEntry(_WorkoutEntry entry, _WorkoutDraft draft) {
    entry
      ..name = draft.name
      ..category = draft.category
      ..sets = draft.sets
      ..reps = draft.reps
      ..minimumWeight = draft.minimumWeight;
    _notifyChanged();
    _persistEntries();
  }

  void deleteEntry(_WorkoutEntry entry) {
    _entries.remove(entry);
    _notifyChanged();
    _persistEntries();
  }

  Future<void> _loadEntries() async {
    final preferences = await SharedPreferences.getInstance();
    final storedEntries = preferences.getStringList(_storageKey) ?? [];
    _entries
      ..clear()
      ..addAll(
        storedEntries.map(
          (encodedEntry) => _WorkoutEntry.fromMap(
            jsonDecode(encodedEntry) as Map<String, dynamic>,
          ),
        ),
      );
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

class _WorkoutDraft {
  const _WorkoutDraft({
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
  @override
  void initState() {
    super.initState();
    widget.module.ready.then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _addWorkout() async {
    final draft = await showDialog<_WorkoutDraft>(
      context: context,
      builder: (context) =>
          _WorkoutEditorDialog(categories: widget.module.categories),
    );
    if (draft != null) {
      widget.module.addEntry(draft);
      setState(() {});
    }
  }

  Future<void> _editWorkout(_WorkoutEntry entry) async {
    final draft = await showDialog<_WorkoutDraft>(
      context: context,
      builder: (context) => _WorkoutEditorDialog(
        entry: entry,
        categories: widget.module.categories,
      ),
    );
    if (draft != null) {
      widget.module.updateEntry(entry, draft);
      setState(() {});
    }
  }

  Future<void> _deleteWorkout(_WorkoutEntry entry) async {
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
      widget.module.deleteEntry(entry);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final entriesByCategory = <String, List<_WorkoutEntry>>{};
    for (final entry in widget.module.entries) {
      entriesByCategory.putIfAbsent(entry.category, () => []).add(entry);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Fitness')),
      body: entriesByCategory.isEmpty
          ? const Center(child: Text('No workouts logged yet.'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: entriesByCategory.entries
                  .map(
                    (category) => _WorkoutCategorySection(
                      category: category.key,
                      entries: category.value,
                      onEdit: _editWorkout,
                      onDelete: _deleteWorkout,
                    ),
                  )
                  .toList(),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addWorkout,
        icon: const Icon(Icons.add),
        label: const Text('Add workout'),
      ),
    );
  }
}

class _WorkoutCategorySection extends StatelessWidget {
  const _WorkoutCategorySection({
    required this.category,
    required this.entries,
    required this.onEdit,
    required this.onDelete,
  });

  final String category;
  final List<_WorkoutEntry> entries;
  final ValueChanged<_WorkoutEntry> onEdit;
  final ValueChanged<_WorkoutEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(category),
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
    )   );
  }
}

class _WorkoutEditorDialog extends StatefulWidget {
  const _WorkoutEditorDialog({required this.categories, this.entry});

  final _WorkoutEntry? entry;
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
      _WorkoutDraft(
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
                value: _selectedCategory,
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
 