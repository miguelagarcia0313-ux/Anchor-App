import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/anchor_module.dart';
import '../../shared/module_bottom_sheet.dart';
import '../../shared/user_cloud_sync.dart';

int _idSequence = 0;

/// Unique even when two entries are created within the same microsecond.
String _newHealthId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${_idSequence++}';

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
  MedicineEntry({
    required this.id,
    required this.name,
    this.firstDoseHour = 8,
    this.firstDoseMinute = 0,
    this.intervalHours = 24,
    this.isTaken = false,
  });

  final String id;
  final String name;
  final int firstDoseHour;
  final int firstDoseMinute;
  final int intervalHours;
  bool isTaken;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'firstDoseHour': firstDoseHour,
    'firstDoseMinute': firstDoseMinute,
    'intervalHours': intervalHours,
    'isTaken': isTaken,
  };

  factory MedicineEntry.fromMap(Map<String, dynamic> map) => MedicineEntry(
    id: map['id'] as String,
    name: map['name'] as String,
    firstDoseHour: map['firstDoseHour'] as int? ?? 8,
    firstDoseMinute: map['firstDoseMinute'] as int? ?? 0,
    intervalHours: map['intervalHours'] as int? ?? 24,
    isTaken: map['isTaken'] as bool? ?? false,
  );
}

class HealthModule implements AnchorModule {
  HealthModule({String? userId, this.onMedicineSaved, this.onMedicineDeleted})
    : _userIdOverride = userId,
      _cloud = UserCloudSync.forCurrentUser(userIdOverride: userId);

  static const _legacyWeightsKey = 'health.weights';
  static const _legacyWaterGoalKey = 'health.water.goal';
  static const _legacyWaterLogKey = 'health.water.daily';
  static const _legacyMedicinesKey = 'health.medicines';
  static const _legacyMedicineDateKey = 'health.medicines.date';
  static const _legacyMigrationKey = 'health.userScopedMigrationComplete';
  static const _weightUnitPreference = 'weightUnit';
  static const _waterHistoryPreference = 'water.history';

  final String? _userIdOverride;
  final Future<void> Function(MedicineEntry medicine)? onMedicineSaved;
  final Future<void> Function(String medicationId)? onMedicineDeleted;

  late final String userId =
      _userIdOverride ??
      (Firebase.apps.isEmpty
          ? 'local'
          : FirebaseAuth.instance.currentUser?.uid ?? 'local');

  String get _weightsKey => 'health.$userId.weights';
  String get _waterGoalKey => 'health.$userId.water.goal';
  String get _waterLogKey => 'health.$userId.water.daily';
  String get _waterHistoryKey => 'health.$userId.$_waterHistoryPreference';
  String get _weightUnitKey => 'health.$userId.$_weightUnitPreference';
  String get _medicinesKey => 'health.$userId.medicines';
  String get _medicineDateKey => 'health.$userId.medicines.date';

  final List<WeightEntry> _weights = [];
  final List<MedicineEntry> _medicines = [];
  final Map<String, double> _waterHistory = {};
  double waterGoalOz = 64;
  double waterTodayOz = 0;
  String weightUnit = 'lb';
  String _dailyDate = _dateKey(DateTime.now());
  bool _resetMedicinesWhenSynced = false;
  final ValueNotifier<int> revision = ValueNotifier(0);
  final UserCloudSync? _cloud;
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

  Map<String, double> get waterHistory => Map.unmodifiable(_waterHistory);

  /// Live summary for the dashboard. Reading [ready] here also makes sure the
  /// module's data (and its medication reminders) load as soon as the card
  /// is shown, not only after the Health screen is opened.
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
                leading: const Icon(Icons.monitor_heart_outlined),
                title: const Text('Health'),
                subtitle: Text(
                  loaded
                      ? _summaryText()
                      : 'Weight, water, medications, and supplements',
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
    final parts = <String>[
      '${_formatNumber(waterTodayOz)}/${_formatNumber(waterGoalOz)} fl oz water',
    ];
    final sortedWeights = weights;
    if (sortedWeights.isNotEmpty) {
      final latest = _weightValue(sortedWeights.last.kilograms, weightUnit);
      parts.add('${_formatNumber(latest)} $weightUnit');
    }
    if (_medicines.isNotEmpty) {
      final taken = _medicines.where((medicine) => medicine.isTaken).length;
      parts.add('$taken/${_medicines.length} meds taken');
    }
    return parts.join(' · ');
  }

  @override
  Widget buildDetailView(BuildContext context) =>
      _HealthDetailView(module: this);

  Future<void> addWeight(double value, String unit) async {
    final entry = WeightEntry(
      id: _newHealthId(),
      kilograms: unit == 'lb' ? value / 2.2046226218 : value,
      recordedAt: DateTime.now(),
    );
    _weights.add(entry);
    _notifyChanged();
    await _saveWeights();
    await _cloud?.records('health', 'weights').doc(entry.id).set(entry.toMap());
  }

  Future<void> updateWeight(
    WeightEntry entry,
    double value,
    String unit,
  ) async {
    entry.kilograms = unit == 'lb' ? value / 2.2046226218 : value;
    _notifyChanged();
    await _saveWeights();
    await _cloud?.records('health', 'weights').doc(entry.id).set(entry.toMap());
  }

  Future<void> deleteWeight(WeightEntry entry) async {
    _weights.remove(entry);
    _notifyChanged();
    await _saveWeights();
    await _cloud?.records('health', 'weights').doc(entry.id).delete();
  }

  /// Puts back an entry removed by [deleteWeight] (used by "Undo").
  Future<void> restoreWeight(WeightEntry entry) async {
    if (_weights.any((existing) => existing.id == entry.id)) return;
    _weights.add(entry);
    _notifyChanged();
    await _saveWeights();
    await _cloud?.records('health', 'weights').doc(entry.id).set(entry.toMap());
  }

  Future<void> setWaterGoal(double ounces) async {
    waterGoalOz = ounces;
    _notifyChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_waterGoalKey, ounces);
    await _cloud?.setModuleSettings('health', 'profile', {
      'waterGoalOz': ounces,
    });
  }

  Future<void> setWeightUnit(String unit) async {
    if (unit != 'lb' && unit != 'kg') return;
    weightUnit = unit;
    _notifyChanged();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_weightUnitKey, unit);
    await _cloud?.setModuleSettings('health', 'profile', {'weightUnit': unit});
  }

  Future<void> addWater(double ounces) async {
    waterTodayOz += ounces;
    _notifyChanged();
    await _saveWaterLog();
  }

  Future<void> removeWater(double ounces) async {
    waterTodayOz = (waterTodayOz - ounces).clamp(0, double.infinity);
    _notifyChanged();
    await _saveWaterLog();
  }

  Future<void> _saveWaterLog() async {
    final preferences = await SharedPreferences.getInstance();
    _waterHistory[_dailyDate] = waterTodayOz;
    final waterLog = {
      'date': _dailyDate,
      'ounces': waterTodayOz,
      'medicineDate': _dailyDate,
    };
    await preferences.setString(_waterLogKey, jsonEncode(waterLog));
    await preferences.setString(_waterHistoryKey, jsonEncode(_waterHistory));
    await _cloud?.records('health', 'days').doc(_dailyDate).set(waterLog);
  }

  Future<void> addMedicine({
    required String name,
    required int firstDoseHour,
    required int firstDoseMinute,
    required int intervalHours,
  }) async {
    final medicine = MedicineEntry(
      id: _newHealthId(),
      name: name,
      firstDoseHour: firstDoseHour,
      firstDoseMinute: firstDoseMinute,
      intervalHours: intervalHours,
    );
    _medicines.add(medicine);
    _notifyChanged();
    await _saveMedicines();
    await onMedicineSaved?.call(medicine);
    await _cloud
        ?.records('health', 'medicines')
        .doc(medicine.id)
        .set(medicine.toMap());
  }

  Future<void> toggleMedicine(MedicineEntry medicine, bool isTaken) async {
    medicine.isTaken = isTaken;
    _notifyChanged();
    await _saveMedicines();
    await _cloud
        ?.records('health', 'medicines')
        .doc(medicine.id)
        .set(medicine.toMap());
  }

  Future<void> deleteMedicine(MedicineEntry medicine) async {
    _medicines.remove(medicine);
    _notifyChanged();
    await _saveMedicines();
    await onMedicineDeleted?.call(medicine.id);
    await _cloud?.records('health', 'medicines').doc(medicine.id).delete();
  }

  Future<void> resetDailyData() async {
    _dailyDate = _dateKey(DateTime.now());
    waterTodayOz = 0;
    for (final medicine in _medicines) {
      medicine.isTaken = false;
    }
    _notifyChanged();
    await _saveWaterLog();
    await _saveMedicines();
    await _persistMedicinesToCloud();
    for (final medicine in _medicines) {
      await onMedicineSaved?.call(medicine);
    }
  }

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateLegacyData(preferences);
    waterGoalOz = preferences.getDouble(_waterGoalKey) ?? 64;
    final savedWeightUnit = preferences.getString(_weightUnitKey);
    if (savedWeightUnit == 'lb' || savedWeightUnit == 'kg') {
      weightUnit = savedWeightUnit!;
    }
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

    final storedWaterHistory = preferences.getString(_waterHistoryKey);
    if (storedWaterHistory != null) {
      final decodedHistory =
          jsonDecode(storedWaterHistory) as Map<String, dynamic>;
      _waterHistory
        ..clear()
        ..addAll(
          decodedHistory.map(
            (date, amount) => MapEntry(date, (amount as num).toDouble()),
          ),
        );
    }

    final today = _dateKey(DateTime.now());
    final waterLog = preferences.getString(_waterLogKey);
    if (waterLog != null) {
      final decoded = jsonDecode(waterLog) as Map<String, dynamic>;
      final loggedDate = decoded['date'] as String?;
      if (loggedDate != null && DateTime.tryParse(loggedDate) != null) {
        _waterHistory[loggedDate] = (decoded['ounces'] as num).toDouble();
      }
    }
    waterTodayOz = _waterHistory[today] ?? 0;
    if (preferences.getString(_medicineDateKey) != today) {
      _dailyDate = today;
      for (final medicine in _medicines) {
        medicine.isTaken = false;
      }
      if (_cloud == null) {
        await _saveMedicines();
      } else {
        await _persistMedicinesLocally();
      }
    } else {
      _dailyDate = today;
    }
    for (final medicine in _medicines) {
      await onMedicineSaved?.call(medicine);
    }
    _notifyChanged();

    final cloud = _cloud;
    if (cloud == null) return;

    await cloud.migrateLocalDataOnce('health', () async {
      await cloud.setRecords(
        'health',
        'weights',
        _weights.map((entry) => MapEntry(entry.id, entry.toMap())),
      );
      await cloud.setRecords(
        'health',
        'medicines',
        _medicines.map((entry) => MapEntry(entry.id, entry.toMap())),
      );
      await cloud.setModuleSettings('health', 'profile', {
        'waterGoalOz': waterGoalOz,
        'weightUnit': weightUnit,
      });
      await cloud.setRecords(
        'health',
        'days',
        _waterHistory.entries.map(
          (entry) => MapEntry(entry.key, {
            'date': entry.key,
            'ounces': entry.value,
            'medicineDate': entry.key == _dailyDate ? _dailyDate : '',
          }),
        ),
      );
      await cloud.records('health', 'days').doc(_dailyDate).set({
        'date': _dailyDate,
        'ounces': waterTodayOz,
        'medicineDate': _dailyDate,
      });
    });

    cloud
        .records('health', 'weights')
        .snapshots()
        .listen(
          (snapshot) {
            _weights
              ..clear()
              ..addAll(
                snapshot.docs.map((document) {
                  return WeightEntry.fromMap(document.data());
                }),
              );
            _notifyChanged();
            unawaited(_persistWeightsLocally());
          },
          onError: (Object error, StackTrace stackTrace) {
            cloud.reportStreamError('health', error, stackTrace);
          },
        );
    cloud
        .records('health', 'medicines')
        .snapshots()
        .listen(
          (snapshot) async {
            for (final change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.removed) {
                await onMedicineDeleted?.call(change.doc.id);
              }
            }
            _medicines
              ..clear()
              ..addAll(
                snapshot.docs.map((document) {
                  return MedicineEntry.fromMap(document.data());
                }),
              );
            if (_resetMedicinesWhenSynced) {
              for (final medicine in _medicines) {
                medicine.isTaken = false;
              }
              unawaited(_persistMedicinesToCloud());
            }
            _notifyChanged();
            unawaited(_persistMedicinesLocally());
            for (final medicine in _medicines) {
              await onMedicineSaved?.call(medicine);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            cloud.reportStreamError('health', error, stackTrace);
          },
        );
    cloud
        .moduleDocument('health')
        .collection('settings')
        .doc('profile')
        .snapshots()
        .listen(
          (snapshot) {
            final waterGoal = snapshot.data()?['waterGoalOz'];
            if (waterGoal is num) {
              waterGoalOz = waterGoal.toDouble();
              unawaited(_persistWaterGoalLocally());
            }
            final syncedWeightUnit = snapshot.data()?['weightUnit'];
            if (syncedWeightUnit == 'lb' || syncedWeightUnit == 'kg') {
              weightUnit = syncedWeightUnit as String;
              unawaited(_persistWeightUnitLocally());
            }
            _notifyChanged();
          },
          onError: (Object error, StackTrace stackTrace) {
            cloud.reportStreamError('health', error, stackTrace);
          },
        );
    cloud
        .records('health', 'days')
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.docs.isEmpty && snapshot.metadata.isFromCache) return;
            _waterHistory
              ..clear()
              ..addEntries(
                snapshot.docs.map((document) {
                  final data = document.data();
                  return MapEntry(
                    data['date'] as String? ?? document.id,
                    (data['ounces'] as num? ?? 0).toDouble(),
                  );
                }),
              );
            final dailyData = snapshot.docs
                .where((document) => document.id == today)
                .firstOrNull
                ?.data();
            waterTodayOz = dailyData == null
                ? 0
                : (dailyData['ounces'] as num? ?? 0).toDouble();
            _dailyDate = today;
            _resetMedicinesWhenSynced = dailyData?['medicineDate'] != today;
            _notifyChanged();
            unawaited(_persistWaterHistoryLocally());
            unawaited(_persistWaterLogLocally());
            if (dailyData?['medicineDate'] != today) {
              for (final medicine in _medicines) {
                medicine.isTaken = false;
              }
              unawaited(_saveMedicines());
              unawaited(_persistMedicinesToCloud());
              unawaited(_saveWaterLog());
              _notifyChanged();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            cloud.reportStreamError('health', error, stackTrace);
          },
        );
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

  Future<void> _persistMedicinesToCloud() async {
    final cloud = _cloud;
    if (cloud == null) return;
    await cloud.setRecords(
      'health',
      'medicines',
      _medicines.map((entry) => MapEntry(entry.id, entry.toMap())),
    );
  }

  Future<void> _persistWeightsLocally() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _weightsKey,
      _weights.map((entry) => jsonEncode(entry.toMap())).toList(),
    );
  }

  Future<void> _persistMedicinesLocally() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _medicinesKey,
      _medicines.map((entry) => jsonEncode(entry.toMap())).toList(),
    );
    await preferences.setString(_medicineDateKey, _dailyDate);
  }

  Future<void> _persistWaterGoalLocally() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_waterGoalKey, waterGoalOz);
  }

  Future<void> _persistWeightUnitLocally() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_weightUnitKey, weightUnit);
  }

  Future<void> _persistWaterHistoryLocally() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_waterHistoryKey, jsonEncode(_waterHistory));
  }

  Future<void> _persistWaterLogLocally() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _waterLogKey,
      jsonEncode({'date': _dailyDate, 'ounces': waterTodayOz}),
    );
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
  static const _quickWaterAmounts = [8, 12, 16, 24];

  Timer? _dailyResetTimer;

  /// How far back the weight card looks. 0 means all entries.
  int _weightRangeDays = 0;

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

  // ---------------------------------------------------------------- weight

  Future<void> _addWeight() async {
    final result = await showModalBottomSheet<_WeightDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          _WeightEditorDialog(initialUnit: widget.module.weightUnit),
    );
    if (result != null) {
      await widget.module.addWeight(result.value, result.unit);
      // Show the weight in the unit it was entered in.
      if (result.unit != widget.module.weightUnit) {
        await widget.module.setWeightUnit(result.unit);
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _editWeight(WeightEntry entry) async {
    final result = await showModalBottomSheet<_WeightDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _WeightEditorDialog(
        entry: entry,
        initialUnit: widget.module.weightUnit,
      ),
    );
    if (result != null) {
      await widget.module.updateWeight(entry, result.value, result.unit);
      if (result.unit != widget.module.weightUnit) {
        await widget.module.setWeightUnit(result.unit);
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _deleteWeightWithUndo(WeightEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final unit = widget.module.weightUnit;
    final label =
        '${_formatNumber(_weightValue(entry.kilograms, unit))} $unit';
    await widget.module.deleteWeight(entry);
    if (!mounted) return;
    setState(() {});
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Deleted $label'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => unawaited(widget.module.restoreWeight(entry)),
          ),
        ),
      );
  }

  Future<void> _showWeightHistory() async {
    final entries = widget.module.weights.reversed.toList();
    final unit = widget.module.weightUnit;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (dialogContext) => ModuleBottomSheet(
        title: 'Weight history',
        actions: Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ),
        child: SizedBox(
          width: 420,
          child: entries.isEmpty
              ? const Text('No weights recorded.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${_formatNumber(_weightValue(entry.kilograms, unit))} '
                        '$unit',
                      ),
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
                              Navigator.pop(dialogContext);
                              await _deleteWeightWithUndo(entry);
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- water

  Future<void> _quickAddWater(double ounces) async {
    await widget.module.addWater(ounces);
    if (mounted) setState(() {});
  }

  Future<void> _addWater() async {
    final amount = await _numberDialog(
      title: 'Add water',
      label: 'Amount in fl oz',
      initialValue: '8',
    );
    if (amount != null && amount > 0) {
      await widget.module.addWater(amount);
      if (mounted) setState(() {});
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
      if (mounted) setState(() {});
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
      if (mounted) setState(() {});
    }
  }

  Future<void> _showWaterHistory() async {
    final history = Map<String, double>.from(widget.module.waterHistory);
    history.putIfAbsent(_dateKey(DateTime.now()), () => 0);
    final goal = widget.module.waterGoalOz;
    final days = history.entries.toList()
      ..sort((first, second) => second.key.compareTo(first.key));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ModuleBottomSheet(
        title: 'Water history',
        actions: Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ),
        child: SizedBox(
          width: 360,
          height: 360,
          child: ListView.separated(
            itemCount: days.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final day = days[index];
              final metGoal = goal > 0 && day.value >= goal;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  metGoal ? Icons.check_circle : Icons.circle_outlined,
                  color: metGoal ? Theme.of(context).colorScheme.primary : null,
                ),
                title: Text(_formatDate(DateTime.parse(day.key))),
                trailing: Text('${_formatNumber(day.value)} fl oz'),
              );
            },
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- medicine

  Future<void> _addMedicine() async {
    final draft = await showModalBottomSheet<_MedicineDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _MedicineEditorDialog(),
    );
    if (draft != null) {
      await widget.module.addMedicine(
        name: draft.name,
        firstDoseHour: draft.firstDoseTime.hour,
        firstDoseMinute: draft.firstDoseTime.minute,
        intervalHours: draft.intervalHours,
      );
      if (mounted) setState(() {});
    }
  }

  Future<void> _confirmRemoveMedicine(MedicineEntry medicine) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${medicine.name}?'),
        content: const Text(
          'This removes it from your daily checklist and deletes its '
          'reminders in Tasks & Reminders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (shouldRemove == true) {
      await widget.module.deleteMedicine(medicine);
      if (mounted) setState(() {});
    }
  }

  Future<double?> _numberDialog({
    required String title,
    required String label,
    required String initialValue,
  }) {
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _NumberEntryDialog(
        title: title,
        label: label,
        initialValue: initialValue,
      ),
    );
  }

  // ----------------------------------------------------------------- build

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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unit = widget.module.weightUnit;
    final allEntries = widget.module.weights;
    final cutoff = _weightRangeDays == 0
        ? null
        : DateTime.now().subtract(Duration(days: _weightRangeDays));
    final entries = cutoff == null
        ? allEntries
        : allEntries
              .where((entry) => !entry.recordedAt.isBefore(cutoff))
              .toList();
    final chartWeights = entries
        .map((entry) => _weightValue(entry.kilograms, unit))
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
    final latest = chartWeights.isEmpty ? null : chartWeights.last;
    final change = chartWeights.length < 2
        ? null
        : chartWeights.last - chartWeights.first;
    final average = chartWeights.isEmpty
        ? null
        : chartWeights.reduce((first, second) => first + second) /
              chartWeights.length;
    final rangeLabel = _weightRangeDays == 0
        ? 'all time'
        : 'last $_weightRangeDays days';

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.monitor_weight_outlined,
            title: 'Weight',
            actions: [
              IconButton(
                onPressed: _showWeightHistory,
                tooltip: 'Edit weight history',
                icon: const Icon(Icons.history),
              ),
              IconButton(
                onPressed: _addWeight,
                tooltip: 'Add weight',
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (allEntries.length > 1)
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7D')),
                    ButtonSegment(value: 30, label: Text('30D')),
                    ButtonSegment(value: 90, label: Text('90D')),
                    ButtonSegment(value: 0, label: Text('All')),
                  ],
                  selected: {_weightRangeDays},
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  onSelectionChanged: (selection) =>
                      setState(() => _weightRangeDays = selection.first),
                ),
              Tooltip(
                message: 'Weight unit',
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'lb', label: Text('lb')),
                    ButtonSegment(value: 'kg', label: Text('kg')),
                  ],
                  selected: {unit},
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  onSelectionChanged: (selection) =>
                      unawaited(widget.module.setWeightUnit(selection.first)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (allEntries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Add a weight to start your graph.')),
            )
          else if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No weigh-ins in this range.')),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'Latest',
                    value: '${_formatNumber(latest!)} $unit',
                    caption: _formatDate(entries.last.recordedAt),
                  ),
                ),
                Expanded(
                  child: _StatTile(
                    label: 'Change',
                    value: change == null
                        ? '—'
                        : '${_formatDelta(change)} $unit',
                    caption: rangeLabel,
                  ),
                ),
                Expanded(
                  child: _StatTile(
                    label: 'Average',
                    value: '${_formatNumber(average!)} $unit',
                    caption:
                        '${entries.length} '
                        '${entries.length == 1 ? 'entry' : 'entries'}',
                  ),
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
                      getTooltipColor: (_) => scheme.inverseSurface,
                      getTooltipItems: (spots) => spots
                          .map(
                            (spot) => LineTooltipItem(
                              '${_formatNumber(spot.y)} $unit',
                              TextStyle(
                                color: scheme.onInverseSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var index = 0; index < chartWeights.length; index++)
                          FlSpot(index.toDouble(), chartWeights[index]),
                      ],
                      isCurved: true,
                      color: scheme.primary,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: scheme.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (entries.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDate(entries.first.recordedAt),
                      style: theme.textTheme.labelSmall,
                    ),
                    Text(
                      _formatDate(entries.last.recordedAt),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _waterSection(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final goal = widget.module.waterGoalOz;
    final today = widget.module.waterTodayOz;
    final progress = goal <= 0
        ? 0.0
        : (today / goal).clamp(0.0, 1.0).toDouble();
    final streak = _waterStreak(widget.module.waterHistory, goal);

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.water_drop_outlined,
            title: 'Water',
            actions: [
              IconButton(
                onPressed: _showWaterHistory,
                tooltip: 'Water history',
                icon: const Icon(Icons.history),
              ),
              IconButton(
                onPressed: _editWaterGoal,
                tooltip: 'Set water goal',
                icon: const Icon(Icons.flag_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                    Text(
                      '${(progress * 100).round()}%',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
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
                      '${_formatNumber(today)} / ${_formatNumber(goal)} fl oz',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      goal > 0 && today >= goal
                          ? 'Goal reached!'
                          : '${_formatNumber((goal - today).clamp(0.0, double.infinity).toDouble())} '
                                'fl oz to go',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.local_fire_department_outlined,
                          size: 18,
                          color: streak > 0
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            streak > 0
                                ? '$streak day streak'
                                : 'Hit your goal to start a streak',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ounces in _quickWaterAmounts)
                ActionChip(
                  label: Text('+$ounces oz'),
                  onPressed: () => _quickAddWater(ounces.toDouble()),
                ),
              ActionChip(
                avatar: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Custom'),
                tooltip: 'Add water',
                onPressed: _addWater,
              ),
              ActionChip(
                avatar: const Icon(Icons.remove, size: 18),
                label: const Text('Remove'),
                tooltip: 'Remove water',
                onPressed: today > 0 ? _removeWater : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Last 7 days',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _WaterWeek(history: widget.module.waterHistory, goal: goal),
        ],
      ),
    );
  }

  Widget _medicineSection(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final medicines = widget.module.medicines;
    final taken = medicines.where((medicine) => medicine.isTaken).length;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.medication_outlined,
            title: 'Medications & Supplements',
            actions: [
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
                'Add medications, vitamins, or supplements to your daily '
                'checklist.',
              ),
            )
          else ...[
            const SizedBox(height: 4),
            Text(
              '$taken of ${medicines.length} taken today',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: taken / medicines.length,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            ...medicines.map(
              (medicine) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  medicine.name,
                  style: TextStyle(
                    decoration: medicine.isTaken
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                subtitle: Text(_scheduleLabel(context, medicine)),
                value: medicine.isTaken,
                onChanged: (checked) async {
                  await widget.module.toggleMedicine(medicine, checked ?? false);
                },
                secondary: IconButton(
                  tooltip: 'Remove item',
                  onPressed: () => _confirmRemoveMedicine(medicine),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
          ],
        ],
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
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final List<Widget> actions;

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
        ...actions,
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.caption,
  });

  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}

/// Seven small bars, one per day, filled relative to the daily water goal.
class _WaterWeek extends StatelessWidget {
  const _WaterWeek({required this.history, required this.goal});

  final Map<String, double> history;
  final double goal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final days = List.generate(
      7,
      (index) => DateTime(now.year, now.month, now.day - (6 - index)),
    );
    const initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: days.map((day) {
        final amount = history[_dateKey(day)] ?? 0;
        final fraction = goal <= 0
            ? 0.0
            : (amount / goal).clamp(0.0, 1.0).toDouble();
        final metGoal = goal > 0 && amount >= goal;
        final isToday = day.day == now.day && day.month == now.month;
        return Expanded(
          child: Tooltip(
            message: '${_formatDate(day)}: ${_formatNumber(amount)} fl oz',
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
                        color: metGoal
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
                    fontWeight: isToday ? FontWeight.w700 : null,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ------------------------------------------------------------------- dialogs

class _WeightDraft {
  const _WeightDraft({required this.value, required this.unit});

  final double value;
  final String unit;
}

class _WeightEditorDialog extends StatefulWidget {
  const _WeightEditorDialog({required this.initialUnit, this.entry});

  final WeightEntry? entry;
  final String initialUnit;

  @override
  State<_WeightEditorDialog> createState() => _WeightEditorDialogState();
}

class _WeightEditorDialogState extends State<_WeightEditorDialog> {
  late final TextEditingController _controller;
  late String _unit;

  @override
  void initState() {
    super.initState();
    _unit = widget.initialUnit;
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
  Widget build(BuildContext context) => ModuleBottomSheet(
    title: widget.entry == null ? 'Add weight' : 'Edit weight',
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
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onSubmitted: (_) => _save(),
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

  void _save() {
    final value = double.tryParse(_controller.text.trim());
    // Stay open on bad input instead of silently closing.
    if (value == null || value <= 0) return;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => ModuleBottomSheet(
    title: widget.title,
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
    child: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onSubmitted: (_) => _save(),
      decoration: InputDecoration(labelText: widget.label),
    ),
  );
}

class _MedicineDraft {
  const _MedicineDraft({
    required this.name,
    required this.firstDoseTime,
    required this.intervalHours,
  });

  final String name;
  final TimeOfDay firstDoseTime;
  final int intervalHours;
}

class _MedicineEditorDialog extends StatefulWidget {
  const _MedicineEditorDialog();

  @override
  State<_MedicineEditorDialog> createState() => _MedicineEditorDialogState();
}

class _MedicineEditorDialogState extends State<_MedicineEditorDialog> {
  final TextEditingController _controller = TextEditingController();
  TimeOfDay _firstDoseTime = const TimeOfDay(hour: 8, minute: 0);
  int _intervalHours = 24;

  Future<void> _chooseFirstDoseTime() async {
    var selectedTime = _firstDoseTime;
    final selected = await showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ModuleBottomSheet(
        title: 'First dose time',
        actions: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(context, selectedTime),
            child: const Text('Save'),
          ),
        ),
        child: SizedBox(
          height: 200,
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.time,
            initialDateTime: DateTime(
              2000,
              1,
              1,
              _firstDoseTime.hour,
              _firstDoseTime.minute,
            ),
            onDateTimeChanged: (value) {
              selectedTime = TimeOfDay.fromDateTime(value);
            },
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _firstDoseTime = selected);
    }
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      _MedicineDraft(
        name: name,
        firstDoseTime: _firstDoseTime,
        intervalHours: _intervalHours,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModuleBottomSheet(
    title: 'Add medication or supplement',
    actions: SizedBox(
      width: double.infinity,
      child: FilledButton(onPressed: _save, child: const Text('Add')),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('First dose'),
          subtitle: Text(
            MaterialLocalizations.of(context).formatTimeOfDay(_firstDoseTime),
          ),
          trailing: IconButton(
            onPressed: _chooseFirstDoseTime,
            tooltip: 'Choose first dose time',
            icon: const Icon(Icons.schedule),
          ),
        ),
        DropdownButtonFormField<int>(
  initialValue: _intervalHours,
  isExpanded: true,                       // new
  decoration: const InputDecoration(labelText: 'Dose frequency'),
  items: List.generate(
    24,
    (index) => DropdownMenuItem(
      value: index + 1,
      child: Text(
        index + 1 == 24
            ? 'Every 24 hours (once daily)'
            : _intervalLabel(index + 1),
        maxLines: 1,                      // new
        overflow: TextOverflow.ellipsis,  // new
      ),
    ),
  ),
  onChanged: (hours) {
    if (hours != null) setState(() => _intervalHours = hours);
  },
),
        const Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Each dose is added to Tasks & Reminders automatically.',
            ),
          ),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------------- helpers

double _weightValue(double kilograms, String unit) =>
    unit == 'lb' ? kilograms * 2.2046226218 : kilograms;

String _formatNumber(double value) {
  final rounded = value.roundToDouble();
  return (value - rounded).abs() < 0.000001
      ? rounded.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

/// Signed change, e.g. "+1.5" or "-2". Tiny changes read as "0".
String _formatDelta(double value) {
  final rounded = (value * 10).round() / 10;
  if (rounded == 0) return '0';
  return '${rounded > 0 ? '+' : ''}${_formatNumber(rounded)}';
}

String _formatDate(DateTime date) => '${date.month}/${date.day}/${date.year}';

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _intervalLabel(int hours) =>
    hours == 1 ? 'Every hour' : 'Every $hours hours';

String _scheduleLabel(BuildContext context, MedicineEntry medicine) {
  final time = MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay(hour: medicine.firstDoseHour, minute: medicine.firstDoseMinute),
  );
  final frequency = medicine.intervalHours == 24
      ? 'Once daily'
      : _intervalLabel(medicine.intervalHours);
  return '$frequency · first dose $time';
}

/// Consecutive days the goal was met. Today only counts once it is met, but an
/// unfinished today doesn't break a streak that runs through yesterday.
int _waterStreak(Map<String, double> history, double goal) {
  if (goal <= 0) return 0;
  var day = DateTime.now();
  var streak = 0;
  var isToday = true;
  while (true) {
    final amount = history[_dateKey(day)] ?? 0;
    if (amount >= goal) {
      streak++;
    } else if (!isToday) {
      break;
    }
    isToday = false;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return streak;
}