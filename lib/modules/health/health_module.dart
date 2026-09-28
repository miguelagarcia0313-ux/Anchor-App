import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/anchor_module.dart';

class WeightEntry {
  WeightEntry({
    required this.id,
    required this.kilograms,
    required this.recordedAt,
  });

  final String id;
  double kilograms;
  DateTime recordedAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'kilograms': kilograms,
    'recordedAt': recordedAt.toIso8601String(),
  };

  factory WeightEntry.fromMap(Map<String, dynamic> map) => WeightEntry(
    id: map['id'] as String,
    kilograms: (map['kilograms'] as num).toDouble(),
    recordedAt: DateTime.parse(map['recordedAt'] as String),
  );
}

class MedicineEntry {
  MedicineEntry({required this.id, required this.name, this.isTaken = false});

  final String id;
  final String name;
  bool isTaken;

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'isTaken': isTaken};

  factory MedicineEntry.fromMap(Map<String, dynamic> map) => MedicineEntry(
    id: map['id'] as String,
    name: map['name'] as String,
    isTaken: map['isTaken'] as bool? ?? false,
  );
}

class HealthModule implements AnchorModule {
  HealthModule({required this.userId});

  static const _legacyWeightsKey = 'health.weights';
  static const _legacyWaterGoalKey = 'health.water.goal';
  static const _legacyWaterLogKey = 'health.water.daily';
  static const _legacyMedicinesKey = 'health.medicines';
  static const _legacyMedicineDateKey = 'health.medicines.date';
  static const _legacyMigrationKey = 'health.userScopedMigrationComplete';

  final String userId;

  String get _weightsKey => 'health.$userId.weights';
  String get _waterGoalKey => 'health.$userId.water.goal';
  String get _waterLogKey => 'health.$userId.water.daily';
  String get _medicinesKey => 'health.$userId.medicines';
  String get _medicineDateKey => 'health.$userId.medicines.date';

  final List<WeightEntry> _weights = [];
  final List<MedicineEntry> _medicines = [];
  double waterGoalOz = 64;
  double waterTodayOz = 0;
  String _dailyDate = _dateKey(DateTime.now());
  final ValueNotifier<int> revision = ValueNotifier(0);
  late final Future<void> ready = _load();

  @override
  String get id => 'health';

  @override
  String get displayName => 'Health';

  List<WeightEntry> get weights {
    final sorted = [..._weights]
      ..sort((first, second) => first.recordedAt.compareTo(second.recordedAt));
    return List.unmodifiable(sorted);
  }

  List<MedicineEntry> get medicines => List.unmodifiable(_medicines);

  @override
  Widget buildSummaryCard(BuildContext context) => const Card(
    child: ListTile(
      leading: Icon(Icons.monitor_heart_outlined),
      title: Text('Health'),
      subtitle: Text('Weight, water, medications, and supplements'),
      trailing: Icon(Icons.chevron_right),
    ),
  );

  @override
  Widget buildDetailView(BuildContext context) =>
      _HealthDetailView(module: this);

  Future<void> addWeight(double value, String unit) async {
    _weights.add(
      WeightEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        kilograms: unit == 'lb' ? value / 2.2046226218 : value,
        recordedAt: DateTime.now(),
      ),
    );
    await _saveWeights();
    _notifyChanged();
  }

  Future<void> updateWeight(
    WeightEntry entry,
    double value,
    String unit,
  ) async {
    entry.kilograms = unit == 'lb' ? value / 2.2046226218 : value;
    await _saveWeights();
    _notifyChanged();
  }

  Future<void> deleteWeight(WeightEntry entry) async {
    _weights.remove(entry);
    await _saveWeights();
    _notifyChanged();
  }

  Future<void> setWaterGoal(double ounces) async {
    waterGoalOz = ounces;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_waterGoalKey, ounces);
    _notifyChanged();
  }

  Future<void> addWater(double ounces) async {
    waterTodayOz += ounces;
    await _saveWaterLog();
    _notifyChanged();
  }

  Future<void> removeWater(double ounces) async {
    waterTodayOz = (waterTodayOz - ounces).clamp(0, double.infinity);
    await _saveWaterLog();
    _notifyChanged();
  }

  Future<void> _saveWaterLog() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _waterLogKey,
      jsonEncode({'date': _dailyDate, 'ounces': waterTodayOz}),
    );
  }

  Future<void> addMedicine(String name) async {
    _medicines.add(
      MedicineEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
      ),
    );
    await _saveMedicines();
    _notifyChanged();
  }

  Future<void> toggleMedicine(MedicineEntry medicine, bool isTaken) async {
    medicine.isTaken = isTaken;
    await _saveMedicines();
    _notifyChanged();
  }

  Future<void> deleteMedicine(MedicineEntry medicine) async {
    _medicines.remove(medicine);
    await _saveMedicines();
    _notifyChanged();
  }

  Future<void> resetDailyData() async {
    _dailyDate = _dateKey(DateTime.now());
    waterTodayOz = 0;
    for (final medicine in _medicines) {
      medicine.isTaken = false;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _waterLogKey,
      jsonEncode({'date': _dailyDate, 'ounces': waterTodayOz}),
    );
    await _saveMedicines();
    _notifyChanged();
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyData(preferences);
    waterGoalOz = preferences.getDouble(_waterGoalKey) ?? 64;
    _weights
      ..clear()
      ..addAll(
        (preferences.getStringList(_weightsKey) ?? []).map(
          (value) =>
              WeightEntry.fromMap(jsonDecode(value) as Map<String, dynamic>),
        ),
      );
    _medicines
      ..clear()
      ..addAll(
        (preferences.getStringList(_medicinesKey) ?? []).map(
          (value) =>
              MedicineEntry.fromMap(jsonDecode(value) as Map<String, dynamic>),
        ),
      );

    final today = _dateKey(DateTime.now());
    final waterLog = preferences.getString(_waterLogKey);
    if (waterLog != null) {
      final decoded = jsonDecode(waterLog) as Map<String, dynamic>;
      if (decoded['date'] == today) {
        waterTodayOz = (decoded['ounces'] as num).toDouble();
      }
    }
    if (preferences.getString(_medicineDateKey) != today) {
      _dailyDate = today;
      for (final medicine in _medicines) {
        medicine.isTaken = false;
      }
      await _saveMedicines();
    } else {
      _dailyDate = today;
    }
    _notifyChanged();
  }

  Future<void> _migrateLegacyData(SharedPreferences preferences) async {
    if (preferences.getBool(_legacyMigrationKey) ?? false) return;

    final legacyWeights = preferences.getStringList(_legacyWeightsKey);
    if (!preferences.containsKey(_weightsKey) && legacyWeights != null) {
      await preferences.setStringList(_weightsKey, legacyWeights);
    }
    final legacyWaterGoal = preferences.getDouble(_legacyWaterGoalKey);
    if (!preferences.containsKey(_waterGoalKey) && legacyWaterGoal != null) {
      await preferences.setDouble(_waterGoalKey, legacyWaterGoal);
    }
    final legacyWaterLog = preferences.getString(_legacyWaterLogKey);
    if (!preferences.containsKey(_waterLogKey) && legacyWaterLog != null) {
      await preferences.setString(_waterLogKey, legacyWaterLog);
    }
    final legacyMedicines = preferences.getStringList(_legacyMedicinesKey);
    if (!preferences.containsKey(_medicinesKey) && legacyMedicines != null) {
      await preferences.setStringList(_medicinesKey, legacyMedicines);
    }
    final legacyMedicineDate = preferences.getString(_legacyMedicineDateKey);
    if (!preferences.containsKey(_medicineDateKey) &&
        legacyMedicineDate != null) {
      await preferences.setString(_medicineDateKey, legacyMedicineDate);
    }

    await preferences.remove(_legacyWeightsKey);
    await preferences.remove(_legacyWaterGoalKey);
    await preferences.remove(_legacyWaterLogKey);
    await preferences.remove(_legacyMedicinesKey);
    await preferences.remove(_legacyMedicineDateKey);
    await preferences.setBool(_legacyMigrationKey, true);
  }

  Future<void> _saveWeights() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _weightsKey,
      _weights.map((entry) => jsonEncode(entry.toMap())).toList(),
    );
  }

  Future<void> _saveMedicines() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _medicinesKey,
      _medicines.map((entry) => jsonEncode(entry.toMap())).toList(),
    );
    await preferences.setString(_medicineDateKey, _dailyDate);
  }

  void _notifyChanged() => revision.value++;
}

class _HealthDetailView extends StatefulWidget {
  const _HealthDetailView({required this.module});

  final HealthModule module;

  @override
  State<_HealthDetailView> createState() => _HealthDetailViewState();
}

class _HealthDetailViewState extends State<_HealthDetailView> {
  Timer? _dailyResetTimer;

  @override
  void initState() {
    super.initState();
    widget.module.ready.then((_) {
      if (mounted) setState(() {});
    });
    _scheduleDailyReset();
  }

  @override
  void dispose() {
    _dailyResetTimer?.cancel();
    super.dispose();
  }

  void _scheduleDailyReset() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _dailyResetTimer = Timer(tomorrow.difference(now), () async {
      await widget.module.resetDailyData();
      if (mounted) {
        setState(() {});
        _scheduleDailyReset();
      }
    });
  }

  Future<void> _addWeight() async {
    final result = await showDialog<_WeightDraft>(
      context: context,
      builder: (context) => const _WeightEditorDialog(),
    );
    if (result != null) {
      await widget.module.addWeight(result.value, result.unit);
      setState(() {});
    }
  }

  Future<void> _editWeight(WeightEntry entry) async {
    final result = await showDialog<_WeightDraft>(
      context: context,
      builder: (context) => _WeightEditorDialog(entry: entry),
    );
    if (result != null) {
      await widget.module.updateWeight(entry, result.value, result.unit);
      setState(() {});
    }
  }

  Future<void> _showWeightHistory() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Weight history'),
        content: SizedBox(
          width: 420,
          child: widget.module.weights.isEmpty
              ? const Text('No weights recorded.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.module.weights.length,
                  itemBuilder: (context, index) {
                    final entry = widget.module.weights[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${_weightValue(entry.kilograms, 'lb')} lb'),
                      subtitle: Text(_formatDate(entry.recordedAt)),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: 'Edit weight',
                            onPressed: () async {
                              Navigator.pop(dialogContext);
                              await _editWeight(entry);
                            },
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Delete weight',
                            onPressed: () async {
                              await widget.module.deleteWeight(entry);
                              if (mounted) setState(() {});
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _addWater() async {
    final amount = await _numberDialog(
      title: 'Add water',
      label: 'Amount in fl oz',
      initialValue: '8',
    );
    if (amount != null && amount > 0) {
      await widget.module.addWater(amount);
      setState(() {});
    }
  }

  Future<void> _removeWater() async {
    final amount = await _numberDialog(
      title: 'Remove water',
      label: 'Amount to subtract in fl oz',
      initialValue: '8',
    );
    if (amount != null && amount > 0) {
      await widget.module.removeWater(amount);
      setState(() {});
    }
  }

  Future<void> _editWaterGoal() async {
    final goal = await _numberDialog(
      title: 'Water goal',
      label: 'Daily goal in fl oz',
      initialValue: _formatNumber(widget.module.waterGoalOz),
    );
    if (goal != null && goal > 0) {
      await widget.module.setWaterGoal(goal);
      setState(() {});
    }
  }

  Future<void> _addMedicine() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _MedicineEditorDialog(),
    );
    if (name != null && name.isNotEmpty) {
      await widget.module.addMedicine(name);
      setState(() {});
    }
  }

  Future<double?> _numberDialog({
    required String title,
    required String label,
    required String initialValue,
  }) {
    return showDialog<double>(
      context: context,
      builder: (context) => _NumberEntryDialog(
        title: title,
        label: label,
        initialValue: initialValue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.module.revision,
      builder: (context, child) => Scaffold(
        appBar: AppBar(title: const Text('Health')),
        body: FutureBuilder<void>(
          future: widget.module.ready,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _weightSection(context),
                const SizedBox(height: 12),
                _waterSection(context),
                const SizedBox(height: 12),
                _medicineSection(context),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _weightSection(BuildContext context) {
    final entries = widget.module.weights;
    final oldest = entries.isEmpty ? null : entries.first;
    final latest = entries.isEmpty ? null : entries.last;
    final chartWeights = entries
        .map((entry) => _weightValue(entry.kilograms, 'lb'))
        .toList();
    final lowestWeight = chartWeights.isEmpty
        ? 0.0
        : chartWeights.reduce(
            (first, second) => first < second ? first : second,
          );
    final highestWeight = chartWeights.isEmpty
        ? 1.0
        : chartWeights.reduce(
            (first, second) => first > second ? first : second,
          );
    final hasWeightRange = highestWeight > lowestWeight;
    final singleWeightPadding = (lowestWeight.abs() * 0.01)
        .clamp(0.5, 1.0)
        .toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Weight',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: _showWeightHistory,
                  tooltip: 'Edit weight history',
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  onPressed: _addWeight,
                  tooltip: 'Add weight',
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Add a weight to start your graph.')),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _EndpointWeight(label: 'Oldest', entry: oldest!),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _EndpointWeight(label: 'Latest', entry: latest!),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: (MediaQuery.sizeOf(context).width * 0.42)
                    .clamp(145.0, 210.0)
                    .toDouble(),
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: entries.length > 1
                        ? (entries.length - 1).toDouble()
                        : 1.0,
                    minY: hasWeightRange
                        ? lowestWeight
                        : lowestWeight - singleWeightPadding,
                    maxY: hasWeightRange
                        ? highestWeight
                        : highestWeight + singleWeightPadding,
                    gridData: const FlGridData(
                      show: true,
                      drawVerticalLine: false,
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: const FlTitlesData(
                      topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) =>
                            Theme.of(context).colorScheme.inverseSurface,
                        getTooltipItems: (spots) => spots
                            .map(
                              (spot) => LineTooltipItem(
                                '${_formatNumber(spot.y)} lb',
                                TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onInverseSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: entries
                            .asMap()
                            .entries
                            .map(
                              (entry) => FlSpot(
                                entry.key.toDouble(),
                                _weightValue(entry.value.kilograms, 'lb'),
                              ),
                            )
                            .toList(),
                        isCurved: true,
                        color: Theme.of(context).colorScheme.primary,
                        barWidth: 3,
                        dotData: const FlDotData(show: true),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _waterSection(BuildContext context) {
    final progress = widget.module.waterGoalOz <= 0
        ? 0.0
        : (widget.module.waterTodayOz / widget.module.waterGoalOz)
              .clamp(0.0, 1.0)
              .toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Water',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: _editWaterGoal,
                  tooltip: 'Set water goal',
                  icon: const Icon(Icons.flag_outlined),
                ),
                IconButton(
                  onPressed: _addWater,
                  tooltip: 'Add water',
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  onPressed: widget.module.waterTodayOz > 0
                      ? _removeWater
                      : null,
                  tooltip: 'Remove water',
                  icon: const Icon(Icons.remove),
                ),
              ],
            ),
            Text(
              '${_formatNumber(widget.module.waterTodayOz)} / '
              '${_formatNumber(widget.module.waterGoalOz)} fl oz',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress, minHeight: 8),
          ],
        ),
      ),
    );
  }

  Widget _medicineSection(BuildContext context) {
    final medicines = widget.module.medicines;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Medications & Supplements',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: _addMedicine,
                  tooltip: 'Add medication or supplement',
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (medicines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Add medications, vitamins, or supplements to your daily checklist.',
                ),
              )
            else
              ...medicines.map(
                (medicine) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(medicine.name),
                  value: medicine.isTaken,
                  onChanged: (checked) {
                    widget.module.toggleMedicine(medicine, checked ?? false);
                  },
                  secondary: IconButton(
                    tooltip: 'Remove item',
                    onPressed: () => widget.module.deleteMedicine(medicine),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EndpointWeight extends StatelessWidget {
  const _EndpointWeight({required this.label, required this.entry});

  final String label;
  final WeightEntry entry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      Text(
        '${_formatNumber(_weightValue(entry.kilograms, 'lb'))} lb',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      Text(_formatDate(entry.recordedAt)),
    ],
  );
}

class _WeightDraft {
  const _WeightDraft({required this.value, required this.unit});

  final double value;
  final String unit;
}

class _WeightEditorDialog extends StatefulWidget {
  const _WeightEditorDialog({this.entry});

  final WeightEntry? entry;

  @override
  State<_WeightEditorDialog> createState() => _WeightEditorDialogState();
}

class _WeightEditorDialogState extends State<_WeightEditorDialog> {
  late final TextEditingController _controller;
  late String _unit;

  @override
  void initState() {
    super.initState();
    _unit = 'lb';
    final initialWeight = widget.entry == null
        ? null
        : _weightValue(widget.entry!.kilograms, _unit);
    _controller = TextEditingController(
      text: initialWeight == null ? '' : _formatNumber(initialWeight),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || value <= 0) return;
    Navigator.pop(context, _WeightDraft(value: value, unit: _unit));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.entry == null ? 'Add weight' : 'Edit weight'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Weight',
            suffix: DropdownButton<String>(
              value: _unit,
              items: const [
                DropdownMenuItem(value: 'lb', child: Text('lb')),
                DropdownMenuItem(value: 'kg', child: Text('kg')),
              ],
              onChanged: (value) {
                if (value == null) return;
                final current = double.tryParse(_controller.text.trim());
                setState(() {
                  if (current != null) {
                    final kilograms = _unit == 'lb'
                        ? current / 2.2046226218
                        : current;
                    final converted = value == 'lb'
                        ? kilograms * 2.2046226218
                        : kilograms;
                    _controller.text = _formatNumber(converted);
                  }
                  _unit = value;
                });
              },
            ),
          ),
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

class _NumberEntryDialog extends StatefulWidget {
  const _NumberEntryDialog({
    required this.title,
    required this.label,
    required this.initialValue,
  });

  final String title;
  final String label;
  final String initialValue;

  @override
  State<_NumberEntryDialog> createState() => _NumberEntryDialogState();
}

class _NumberEntryDialogState extends State<_NumberEntryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: widget.label),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, double.tryParse(_controller.text.trim())),
        child: const Text('Save'),
      ),
    ],
  );
}

class _MedicineEditorDialog extends StatefulWidget {
  const _MedicineEditorDialog();

  @override
  State<_MedicineEditorDialog> createState() => _MedicineEditorDialogState();
}

class _MedicineEditorDialogState extends State<_MedicineEditorDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add medicine or vitamin'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(labelText: 'Name'),
      onSubmitted: (value) => Navigator.pop(context, value.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Add'),
      ),
    ],
  );
}

double _weightValue(double kilograms, String unit) =>
    unit == 'lb' ? kilograms * 2.2046226218 : kilograms;

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
