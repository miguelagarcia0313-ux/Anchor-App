import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/anchor_module.dart';
import '../../shared/module_bottom_sheet.dart';
import '../../shared/user_cloud_sync.dart';

int _idSequence = 0;

/// Unique even when two meals are created within the same microsecond.
String _newMealId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${_idSequence++}';

class MealEntry {
  MealEntry({
    required this.id,
    required this.name,
    required this.calories,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.sugarGrams,
    required this.loggedAt,
  });

  final String id;
  String name;
  double calories;
  double proteinGrams;
  double carbsGrams;
  double sugarGrams;
  DateTime loggedAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'calories': calories,
    'proteinGrams': proteinGrams,
    'carbsGrams': carbsGrams,
    'sugarGrams': sugarGrams,
    'loggedAt': loggedAt.toIso8601String(),
  };

  factory MealEntry.fromMap(Map<String, dynamic> map) => MealEntry(
    id: map['id'] as String,
    name: map['name'] as String? ?? '',
    calories: (map['calories'] as num?)?.toDouble() ?? 0,
    proteinGrams: (map['proteinGrams'] as num?)?.toDouble() ?? 0,
    carbsGrams: (map['carbsGrams'] as num?)?.toDouble() ?? 0,
    sugarGrams: (map['sugarGrams'] as num?)?.toDouble() ?? 0,
    loggedAt: DateTime.parse(map['loggedAt'] as String),
  );
}

/// The values a meal is saved from.
///
/// Manual entry builds one of these in the editor. A later photo flow can ask
/// Gemini for the same four numbers, wrap them in a [MealDraft], and open the
/// same editor pre-filled so the user can review and correct the estimate.
class MealDraft {
  const MealDraft({
    required this.name,
    required this.calories,
    this.proteinGrams = 0,
    this.carbsGrams = 0,
    this.sugarGrams = 0,
  });

  final String name;
  final double calories;
  final double proteinGrams;
  final double carbsGrams;
  final double sugarGrams;
}

/// Daily targets. Defaults are the standard 2,000 kcal reference diet.
class NutritionGoals {
  const NutritionGoals({
    this.calories = 2000,
    this.proteinGrams = 50,
    this.carbsGrams = 275,
    this.sugarGrams = 50,
  });

  final double calories;
  final double proteinGrams;
  final double carbsGrams;
  final double sugarGrams;

  Map<String, dynamic> toMap() => {
    'calories': calories,
    'proteinGrams': proteinGrams,
    'carbsGrams': carbsGrams,
    'sugarGrams': sugarGrams,
  };

  factory NutritionGoals.fromMap(Map<String, dynamic> map) {
    const defaults = NutritionGoals();
    return NutritionGoals(
      calories: (map['calories'] as num?)?.toDouble() ?? defaults.calories,
      proteinGrams:
          (map['proteinGrams'] as num?)?.toDouble() ?? defaults.proteinGrams,
      carbsGrams:
          (map['carbsGrams'] as num?)?.toDouble() ?? defaults.carbsGrams,
      sugarGrams:
          (map['sugarGrams'] as num?)?.toDouble() ?? defaults.sugarGrams,
    );
  }
}

class NutritionTotals {
  const NutritionTotals({
    this.calories = 0,
    this.proteinGrams = 0,
    this.carbsGrams = 0,
    this.sugarGrams = 0,
    this.mealCount = 0,
  });

  final double calories;
  final double proteinGrams;
  final double carbsGrams;
  final double sugarGrams;
  final int mealCount;
}

class NutritionModule implements AnchorModule {
  NutritionModule({String? userId})
    : _userIdOverride = userId,
      _cloud = UserCloudSync.forCurrentUser(userIdOverride: userId);

  final String? _userIdOverride;

  late final String userId =
      _userIdOverride ??
      (Firebase.apps.isEmpty
          ? 'local'
          : FirebaseAuth.instance.currentUser?.uid ?? 'local');

  String get _mealsKey => 'nutrition.$userId.meals';
  String get _goalsKey => 'nutrition.$userId.goals';

  final List<MealEntry> _meals = [];
  NutritionGoals goals = const NutritionGoals();
  final ValueNotifier<int> revision = ValueNotifier(0);
  final UserCloudSync? _cloud;
  late final Future<void> ready = _load();

  @override
  String get id => 'nutrition';

  @override
  String get displayName => 'Nutrition';

  /// Every meal, oldest first.
  List<MealEntry> get meals {
    final sorted = [..._meals]
      ..sort((first, second) => first.loggedAt.compareTo(second.loggedAt));
    return List.unmodifiable(sorted);
  }

  /// Meals logged on [day] (local time), oldest first.
  List<MealEntry> mealsOn(DateTime day) {
    final key = _dateKey(day);
    return List.unmodifiable(
      meals.where((meal) => _dateKey(meal.loggedAt) == key),
    );
  }

  NutritionTotals totalsOn(DateTime day) {
    final dayMeals = mealsOn(day);
    var calories = 0.0;
    var protein = 0.0;
    var carbs = 0.0;
    var sugar = 0.0;
    for (final meal in dayMeals) {
      calories += meal.calories;
      protein += meal.proteinGrams;
      carbs += meal.carbsGrams;
      sugar += meal.sugarGrams;
    }
    return NutritionTotals(
      calories: calories,
      proteinGrams: protein,
      carbsGrams: carbs,
      sugarGrams: sugar,
      mealCount: dayMeals.length,
    );
  }

  @override
  Widget buildSummaryCard(BuildContext context) {
    return FutureBuilder<void>(
      future: ready,
      builder: (context, snapshot) {
        return ValueListenableBuilder<int>(
          valueListenable: revision,
          builder: (context, revisionValue, child) {
            final loaded = snapshot.connectionState == ConnectionState.done;
            return Card(
              child: ListTile(
                leading: const Icon(Icons.restaurant_outlined),
                title: const Text('Nutrition'),
                subtitle: Text(
                  loaded
                      ? _summaryText()
                      : 'Calories, protein, carbs, and sugar',
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            );
          },
        );
      },
    );
  }

  String _summaryText() {
    final totals = totalsOn(DateTime.now());
    if (totals.mealCount == 0) {
      return 'Nothing logged today · ${_formatNumber(goals.calories)} kcal goal';
    }
    return '${_formatNumber(totals.calories)} / '
        '${_formatNumber(goals.calories)} kcal · '
        '${_formatNumber(totals.proteinGrams)} g protein';
  }

  @override
  Widget buildDetailView(BuildContext context) =>
      _NutritionDetailView(module: this);

  /// Logs a meal. [loggedAt] defaults to now; pass a date to log a past day.
  Future<void> addMeal(MealDraft draft, {DateTime? loggedAt}) async {
    final entry = MealEntry(
      id: _newMealId(),
      name: draft.name,
      calories: draft.calories,
      proteinGrams: draft.proteinGrams,
      carbsGrams: draft.carbsGrams,
      sugarGrams: draft.sugarGrams,
      loggedAt: loggedAt ?? DateTime.now(),
    );
    _meals.add(entry);
    _notifyChanged();
    await _saveMeals();
    await _saveMealToCloud(entry);
  }

  Future<void> updateMeal(MealEntry entry, MealDraft draft) async {
    entry
      ..name = draft.name
      ..calories = draft.calories
      ..proteinGrams = draft.proteinGrams
      ..carbsGrams = draft.carbsGrams
      ..sugarGrams = draft.sugarGrams;
    _notifyChanged();
    await _saveMeals();
    await _saveMealToCloud(entry);
  }

  Future<void> deleteMeal(MealEntry entry) async {
    _meals.remove(entry);
    _notifyChanged();
    await _saveMeals();
    await _cloud?.records('nutrition', 'meals').doc(entry.id).delete();
  }

  /// Puts back a meal removed by [deleteMeal] (used by "Undo").
  Future<void> restoreMeal(MealEntry entry) async {
    if (_meals.any((existing) => existing.id == entry.id)) return;
    _meals.add(entry);
    _notifyChanged();
    await _saveMeals();
    await _saveMealToCloud(entry);
  }

  Future<void> setGoals(NutritionGoals newGoals) async {
    goals = newGoals;
    _notifyChanged();
    await _saveGoalsLocally();
    await _cloud?.setModuleSettings('nutrition', 'profile', goals.toMap());
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    _meals
      ..clear()
      ..addAll(
        (preferences.getStringList(_mealsKey) ?? []).map(
          (value) =>
              MealEntry.fromMap(jsonDecode(value) as Map<String, dynamic>),
        ),
      );
    final storedGoals = preferences.getString(_goalsKey);
    if (storedGoals != null) {
      goals = NutritionGoals.fromMap(
        jsonDecode(storedGoals) as Map<String, dynamic>,
      );
    }
    _notifyChanged();

    final cloud = _cloud;
    if (cloud == null) return;

    await cloud.migrateLocalDataOnce('nutrition', () async {
      await cloud.setRecords(
        'nutrition',
        'meals',
        _meals.map((entry) => MapEntry(entry.id, entry.toMap())),
      );
      await cloud.setModuleSettings('nutrition', 'profile', goals.toMap());
    });

    cloud
        .records('nutrition', 'meals')
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.docs.isEmpty && snapshot.metadata.isFromCache) return;
            _meals
              ..clear()
              ..addAll(
                snapshot.docs.map((document) {
                  return MealEntry.fromMap(document.data());
                }),
              );
            _notifyChanged();
            unawaited(_saveMeals());
          },
          onError: (Object error, StackTrace stackTrace) {
            cloud.reportStreamError('nutrition', error, stackTrace);
          },
        );
    cloud
        .moduleDocument('nutrition')
        .collection('settings')
        .doc('profile')
        .snapshots()
        .listen(
          (snapshot) {
            final data = snapshot.data();
            if (data == null) return;
            goals = NutritionGoals.fromMap(data);
            _notifyChanged();
            unawaited(_saveGoalsLocally());
          },
          onError: (Object error, StackTrace stackTrace) {
            cloud.reportStreamError('nutrition', error, stackTrace);
          },
        );
  }

  Future<void> _saveMeals() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _mealsKey,
      _meals.map((entry) => jsonEncode(entry.toMap())).toList(),
    );
  }

  Future<void> _saveGoalsLocally() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_goalsKey, jsonEncode(goals.toMap()));
  }

  Future<void> _saveMealToCloud(MealEntry entry) async {
    await _cloud
        ?.records('nutrition', 'meals')
        .doc(entry.id)
        .set(entry.toMap());
  }

  void _notifyChanged() => revision.value++;
}

class _NutritionDetailView extends StatefulWidget {
  const _NutritionDetailView({required this.module});

  final NutritionModule module;

  @override
  State<_NutritionDetailView> createState() => _NutritionDetailViewState();
}

class _NutritionDetailViewState extends State<_NutritionDetailView> {
  /// The day being viewed. Null means "today", so the screen follows the
  /// calendar if it stays open past midnight.
  DateTime? _pickedDay;

  DateTime get _today => _dateOnly(DateTime.now());
  DateTime get _day => _pickedDay ?? _today;

  void _selectDay(DateTime day) {
    final selected = _dateOnly(day);
    setState(() => _pickedDay = _isSameDay(selected, _today) ? null : selected);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: _today,
    );
    if (picked != null) _selectDay(picked);
  }

  Future<void> _addMeal() async {
    final draft = await showModalBottomSheet<MealDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _MealEditorSheet(),
    );
    if (draft == null) return;
    final day = _day;
    final now = DateTime.now();
    // Meals added to a past day are stamped at noon of that day.
    final loggedAt = _isSameDay(day, now)
        ? now
        : DateTime(day.year, day.month, day.day, 12);
    await widget.module.addMeal(draft, loggedAt: loggedAt);
  }

  Future<void> _editMeal(MealEntry entry) async {
    final draft = await showModalBottomSheet<MealDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _MealEditorSheet(entry: entry),
    );
    if (draft != null) {
      await widget.module.updateMeal(entry, draft);
    }
  }

  Future<void> _deleteWithUndo(MealEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final deletion = widget.module.deleteMeal(entry);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Deleted "${entry.name}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => unawaited(widget.module.restoreMeal(entry)),
          ),
        ),
      );
    await deletion;
  }

  Future<void> _editGoals() async {
    final result = await showModalBottomSheet<NutritionGoals>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _GoalsSheet(goals: widget.module.goals),
    );
    if (result != null) {
      await widget.module.setGoals(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: widget.module.ready,
      builder: (context, snapshot) {
        final loaded = snapshot.connectionState == ConnectionState.done;
        return AnimatedBuilder(
          animation: widget.module.revision,
          builder: (context, child) => Scaffold(
            appBar: AppBar(
              title: const Text('Nutrition'),
              actions: [
                IconButton(
                  tooltip: 'Set nutrition goals',
                  onPressed: loaded ? _editGoals : null,
                  icon: const Icon(Icons.flag_outlined),
                ),
              ],
            ),
            body: loaded
                ? _buildBody(context)
                : const Center(child: CircularProgressIndicator()),
            // Hidden until loaded so a meal can't be added and then wiped by
            // the initial load.
            floatingActionButton: loaded
                ? FloatingActionButton.extended(
                    onPressed: _addMeal,
                    icon: const Icon(Icons.add),
                    label: const Text('Add meal'),
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final day = _day;
    final dayMeals = widget.module.mealsOn(day);
    final totals = widget.module.totalsOn(day);
    final goals = widget.module.goals;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        _dayNavigator(context),
        const SizedBox(height: 8),
        _totalsCard(context, totals, goals),
        const SizedBox(height: 12),
        _mealsCard(context, dayMeals),
        const SizedBox(height: 12),
        _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHeader(
                icon: Icons.bar_chart_outlined,
                title: 'Last 7 days',
              ),
              const SizedBox(height: 12),
              _CalorieWeek(
                module: widget.module,
                selectedDay: day,
                onSelect: _selectDay,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dayNavigator(BuildContext context) {
    final day = _day;
    final isToday = _isSameDay(day, _today);
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous day',
          onPressed: () => _selectDay(DateTime(day.year, day.month, day.day - 1)),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Center(
            child: Tooltip(
              message: 'Pick a date',
              child: TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(_dayLabel(context, day)),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next day',
          onPressed: isToday
              ? null
              : () => _selectDay(DateTime(day.year, day.month, day.day + 1)),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _totalsCard(
    BuildContext context,
    NutritionTotals totals,
    NutritionGoals goals,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final remaining = goals.calories - totals.calories;
    final progress = goals.calories <= 0
        ? 0.0
        : (totals.calories / goals.calories).clamp(0.0, 1.0).toDouble();

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 10,
                        strokeCap: StrokeCap.round,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatNumber(totals.calories),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text('kcal', style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_formatNumber(totals.calories)} / '
                      '${_formatNumber(goals.calories)} kcal',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      remaining >= 0
                          ? '${_formatNumber(remaining)} kcal left'
                          : 'Over by ${_formatNumber(-remaining)} kcal',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: remaining < 0
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${totals.mealCount} '
                      '${totals.mealCount == 1 ? 'meal' : 'meals'} logged',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MacroBar(
            label: 'Protein',
            value: totals.proteinGrams,
            goal: goals.proteinGrams,
          ),
          const SizedBox(height: 12),
          _MacroBar(
            label: 'Carbs',
            value: totals.carbsGrams,
            goal: goals.carbsGrams,
          ),
          const SizedBox(height: 12),
          _MacroBar(
            label: 'Sugar',
            value: totals.sugarGrams,
            goal: goals.sugarGrams,
            warnWhenOver: true,
          ),
        ],
      ),
    );
  }

  Widget _mealsCard(BuildContext context, List<MealEntry> meals) {
    final isToday = _isSameDay(_day, _today);
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(icon: Icons.restaurant_outlined, title: 'Meals'),
          if (meals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No meals logged for ${isToday ? 'today' : 'this day'}.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: _addMeal,
                      child: const Text('Log a meal'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            ...meals.map((meal) => _mealTile(context, meal)),
          ],
        ],
      ),
    );
  }

  Widget _mealTile(BuildContext context, MealEntry entry) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(entry.loggedAt));
    return Padding(
      key: ValueKey('meal:${entry.id}'),
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
            onTap: () => _editMeal(entry),
            title: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '$time · P ${_formatNumber(entry.proteinGrams)}g · '
              'C ${_formatNumber(entry.carbsGrams)}g · '
              'S ${_formatNumber(entry.sugarGrams)}g',
            ),
            trailing: Text(
              '${_formatNumber(entry.calories)} kcal',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ shared widgets

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _MacroBar extends StatelessWidget {
  const _MacroBar({
    required this.label,
    required this.value,
    required this.goal,
    this.warnWhenOver = false,
  });

  final String label;
  final double value;
  final double goal;

  /// Colors the bar as a warning once the goal is passed (used for sugar).
  final bool warnWhenOver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = goal <= 0
        ? 0.0
        : (value / goal).clamp(0.0, 1.0).toDouble();
    final isOver = warnWhenOver && goal > 0 && value > goal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Text(
              '${_formatNumber(value)} / ${_formatNumber(goal)} g',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isOver ? scheme.error : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            color: isOver ? scheme.error : null,
          ),
        ),
      ],
    );
  }
}

/// Seven bars (calories vs. goal), one per day. Tap a bar to open that day.
class _CalorieWeek extends StatelessWidget {
  const _CalorieWeek({
    required this.module,
    required this.selectedDay,
    required this.onSelect,
  });

  final NutritionModule module;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final goal = module.goals.calories;
    final days = List.generate(
      7,
      (index) => DateTime(now.year, now.month, now.day - (6 - index)),
    );
    const initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: days.map((day) {
        final calories = module.totalsOn(day).calories;
        final fraction = goal <= 0
            ? 0.0
            : (calories / goal).clamp(0.0, 1.0).toDouble();
        final isSelected = _isSameDay(day, selectedDay);
        return Expanded(
          child: Tooltip(
            message: '${_formatDate(day)}: ${_formatNumber(calories)} kcal',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(day),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 52,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 16,
                        height: 6 + 46 * fraction,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? scheme.primary
                              : scheme.primary.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    initials[day.weekday - 1],
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: isSelected ? FontWeight.w700 : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ------------------------------------------------------------------- sheets

class _MealEditorSheet extends StatefulWidget {
  const _MealEditorSheet({this.entry});

  final MealEntry? entry;

  @override
  State<_MealEditorSheet> createState() => _MealEditorSheetState();
}

class _MealEditorSheetState extends State<_MealEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _sugarController;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    String initial(double? value) =>
        value == null ? '' : _formatNumber(value);
    _nameController = TextEditingController(text: entry?.name);
    _caloriesController = TextEditingController(text: initial(entry?.calories));
    _proteinController = TextEditingController(
      text: initial(entry?.proteinGrams),
    );
    _carbsController = TextEditingController(text: initial(entry?.carbsGrams));
    _sugarController = TextEditingController(text: initial(entry?.sugarGrams));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _sugarController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      MealDraft(
        name: _nameController.text.trim(),
        calories: _parse(_caloriesController.text),
        proteinGrams: _parse(_proteinController.text),
        carbsGrams: _parse(_carbsController.text),
        sugarGrams: _parse(_sugarController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ModuleBottomSheet(
      title: widget.entry == null ? 'Add meal' : 'Edit meal',
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
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Meal name'),
              validator: _requiredText,
            ),
            TextFormField(
              controller: _caloriesController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Calories',
                suffixText: 'kcal',
              ),
              validator: _requiredNumber,
            ),
            TextFormField(
              controller: _proteinController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Protein',
                suffixText: 'g',
              ),
              validator: _optionalNumber,
            ),
            TextFormField(
              controller: _carbsController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Carbs',
                suffixText: 'g',
              ),
              validator: _optionalNumber,
            ),
            TextFormField(
              controller: _sugarController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Sugar',
                suffixText: 'g',
                helperText: 'Sugar is part of your carbs.',
              ),
              validator: _optionalNumber,
              onFieldSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalsSheet extends StatefulWidget {
  const _GoalsSheet({required this.goals});

  final NutritionGoals goals;

  @override
  State<_GoalsSheet> createState() => _GoalsSheetState();
}

class _GoalsSheetState extends State<_GoalsSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _sugarController;

  @override
  void initState() {
    super.initState();
    final goals = widget.goals;
    _caloriesController = TextEditingController(
      text: _formatNumber(goals.calories),
    );
    _proteinController = TextEditingController(
      text: _formatNumber(goals.proteinGrams),
    );
    _carbsController = TextEditingController(
      text: _formatNumber(goals.carbsGrams),
    );
    _sugarController = TextEditingController(
      text: _formatNumber(goals.sugarGrams),
    );
  }

  @override
  void dispose() {
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _sugarController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      NutritionGoals(
        calories: _parse(_caloriesController.text),
        proteinGrams: _parse(_proteinController.text),
        carbsGrams: _parse(_carbsController.text),
        sugarGrams: _parse(_sugarController.text),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String suffix, {
    bool last = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      validator: _positiveNumber,
      onFieldSubmitted: last ? (_) => _save() : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ModuleBottomSheet(
      title: 'Daily goals',
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
            _field(_caloriesController, 'Calories', 'kcal'),
            _field(_proteinController, 'Protein', 'g'),
            _field(_carbsController, 'Carbs', 'g'),
            _field(_sugarController, 'Sugar', 'g', last: true),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- helpers

double _parse(String text) => double.tryParse(text.trim()) ?? 0;

String? _requiredText(String? value) {
  if (value == null || value.trim().isEmpty) return 'Required';
  return null;
}

String? _requiredNumber(String? value) {
  final number = double.tryParse((value ?? '').trim());
  if (number == null || number < 0) return 'Enter 0 or more';
  return null;
}

/// Blank is fine (counts as 0); anything typed must be a valid number.
String? _optionalNumber(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;
  final number = double.tryParse(text);
  if (number == null || number < 0) return 'Enter 0 or more';
  return null;
}

String? _positiveNumber(String? value) {
  final number = double.tryParse((value ?? '').trim());
  if (number == null || number <= 0) return 'Enter a number greater than 0';
  return null;
}

String _formatNumber(double value) {
  final rounded = value.roundToDouble();
  return (value - rounded).abs() < 0.000001
      ? rounded.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

String _formatDate(DateTime date) => '${date.month}/${date.day}/${date.year}';

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

bool _isSameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

String _dayLabel(BuildContext context, DateTime day) {
  final today = _dateOnly(DateTime.now());
  if (_isSameDay(day, today)) return 'Today';
  if (_isSameDay(day, DateTime(today.year, today.month, today.day - 1))) {
    return 'Yesterday';
  }
  return MaterialLocalizations.of(context).formatMediumDate(day);
}