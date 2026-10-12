import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'finance_expense.dart';

/// Starting budgets for a brand-new user, until they edit them on the
/// category screen. After that, the values saved in Firestore win.
///
/// (These used to be `_demoBudgets` in finance_module.dart. They're still
/// numbers in code, but now they're only *defaults*, not the data.)
const Map<String, double> defaultBudgets = {
  'groceries': 150.0,
  'eating_out': 100.0,
  'subscriptions': 30.0,
  'entertainment': 50.0,
  'miscellaneous': 50.0,
};

/// How far back the Finance screen loads expenses. Covers this month's
/// budget pace, the 30-day savings projection, and the recent list.
const Duration financeLookback = Duration(days: 120);

/// Everything the Finance UI needs from storage, behind one interface.
///
/// Why an interface: the UI and the insights math never import Firestore.
/// The real app uses [FirestoreFinanceRepository]; widget tests (and later,
/// BDD seeding) use [InMemoryFinanceRepository] with exact values.
abstract class FinanceRepository {
  /// Emits a new snapshot every time expenses, budgets, or bank status
  /// change -- including changes made by Cloud Functions on the server.
  Stream<FinanceSnapshot> watch();

  Future<void> addManualExpense({
    required double amount,
    required String category,
    required DateTime date,
    String? note,
  });

  /// Only manual expenses can be deleted (bank data mirrors the bank).
  Future<void> deleteManualExpense(String id);

  /// Saves the user's own category for an expense (Plaid or manual).
  Future<void> setUserCategory(String expenseId, String category);

  Future<void> setBudget(String category, double amount);
}

class FirestoreFinanceRepository implements FinanceRepository {
  FirestoreFinanceRepository({
    required this.uid,
    FirebaseFirestore? firestore,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _expenses =>
      _db.collection('users').doc(uid).collection('expenses');

  DocumentReference<Map<String, dynamic>> get _settings =>
      _db.collection('users').doc(uid).collection('settings').doc('finance');

  @override
  Stream<FinanceSnapshot> watch() {
    final since = FinanceExpense.formatDate(
      DateTime.now().subtract(financeLookback),
    );
    // Dates are stored as "YYYY-MM-DD" strings, which sort the same way
    // alphabetically as they do chronologically -- so a string range
    // query works, and no composite index is needed.
    final expenses = _expenses
        .where('date', isGreaterThanOrEqualTo: since)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => FinanceExpense.fromMap(d.id, d.data()))
            .toList());

    final settings = _settings.snapshots().map((snap) => snap.data());

    return combineLatest2(expenses, settings, (list, settingsData) {
      return FinanceSnapshot(
        expenses: list,
        budgets: parseBudgets(settingsData?['budgets']),
        bank: _parseBank(settingsData?['bank']),
      );
    });
  }

  @override
  Future<void> addManualExpense({
    required double amount,
    required String category,
    required DateTime date,
    String? note,
  }) {
    return _expenses.add({
      ...FinanceExpense.manualMap(
        amount: amount,
        date: date,
        category: category,
        note: note,
      ),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> deleteManualExpense(String id) => _expenses.doc(id).delete();

  @override
  Future<void> setUserCategory(String expenseId, String category) {
    return _expenses.doc(expenseId).update({'userCategory': category});
  }

  @override
  Future<void> setBudget(String category, double amount) {
    // merge: true deep-merges the map, so other categories' budgets stay.
    return _settings.set({
      'budgets': {category: amount},
    }, SetOptions(merge: true));
  }

  static BankStatus _parseBank(Object? raw) {
    if (raw is! Map) return BankStatus.disconnected;
    final synced = raw['lastSyncedAt'];
    return BankStatus(
      connected: raw['connected'] == true,
      institutionName: raw['institutionName'] as String?,
      lastSyncedAt: synced is Timestamp ? synced.toDate() : null,
    );
  }
}

/// Saved budgets layered on top of [defaultBudgets]. Ignores junk values
/// (Firestore has no schema) and anything that isn't a known category.
Map<String, double> parseBudgets(Object? raw) {
  final result = Map<String, double>.of(defaultBudgets);
  if (raw is Map) {
    raw.forEach((key, value) {
      if (result.containsKey(key) && value is num && value > 0) {
        result[key as String] = value.toDouble();
      }
    });
  }
  return result;
}

/// Emits [combine](a, b) whenever either stream emits, once both have
/// emitted at least once. (Same idea as RxDart's combineLatest2 -- written
/// out here so we don't add a dependency for one function.)
Stream<R> combineLatest2<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A, B) combine,
) {
  late StreamController<R> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  A? lastA;
  B? lastB;
  var hasA = false;
  var hasB = false;
  var openSources = 2;

  void emit() {
    if (hasA && hasB) controller.add(combine(lastA as A, lastB as B));
  }

  // Firestore snapshot streams never finish, but finite streams (tests)
  // should close the combined stream once both sources are done.
  void sourceDone() {
    if (--openSources == 0) controller.close();
  }

  controller = StreamController<R>(
    onListen: () {
      subA = a.listen((v) {
        lastA = v;
        hasA = true;
        emit();
      }, onError: controller.addError, onDone: sourceDone);
      subB = b.listen((v) {
        lastB = v;
        hasB = true;
        emit();
      }, onError: controller.addError, onDone: sourceDone);
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return controller.stream;
}

/// A repository that lives only in memory. Used by widget tests, and handy
/// for demos/BDD seeding because you control every value exactly.
class InMemoryFinanceRepository implements FinanceRepository {
  InMemoryFinanceRepository({
    List<FinanceExpense> expenses = const [],
    Map<String, double>? budgets,
    BankStatus bank = BankStatus.disconnected,
  })  : _expenses = List.of(expenses),
        _budgets = Map.of(budgets ?? defaultBudgets),
        // ignore: prefer_initializing_formals -- keeps the public `bank:` parameter name
        _bank = bank;

  final List<FinanceExpense> _expenses;
  final Map<String, double> _budgets;
  BankStatus _bank;
  final _changes = StreamController<FinanceSnapshot>.broadcast();
  int _nextId = 1;

  FinanceSnapshot get current => FinanceSnapshot(
        expenses: List.unmodifiable(
          List.of(_expenses)..sort((x, y) => y.date.compareTo(x.date)),
        ),
        budgets: Map.unmodifiable(_budgets),
        bank: _bank,
      );

  void _notify() => _changes.add(current);

  @override
  Stream<FinanceSnapshot> watch() async* {
    yield current;
    yield* _changes.stream;
  }

  /// Test helper: pretend Cloud Functions imported these.
  void importFromBank(List<FinanceExpense> expenses, {String? institution}) {
    _expenses.addAll(expenses);
    _bank = BankStatus(
      connected: true,
      institutionName: institution ?? _bank.institutionName,
      lastSyncedAt: DateTime.now(),
    );
    _notify();
  }

  @override
  Future<void> addManualExpense({
    required double amount,
    required String category,
    required DateTime date,
    String? note,
  }) async {
    _expenses.add(FinanceExpense(
      id: 'manual-${_nextId++}',
      amount: amount,
      date: date,
      autoCategory: category,
      merchantName: note,
      source: 'manual',
    ));
    _notify();
  }

  @override
  Future<void> deleteManualExpense(String id) async {
    _expenses.removeWhere((e) => e.id == id && e.isManual);
    _notify();
  }

  @override
  Future<void> setUserCategory(String expenseId, String category) async {
    final i = _expenses.indexWhere((e) => e.id == expenseId);
    if (i == -1) return;
    final old = _expenses[i];
    _expenses[i] = FinanceExpense(
      id: old.id,
      amount: old.amount,
      date: old.date,
      autoCategory: old.autoCategory,
      userCategory: category,
      merchantName: old.merchantName,
      pending: old.pending,
      source: old.source,
    );
    _notify();
  }

  @override
  Future<void> setBudget(String category, double amount) async {
    _budgets[category] = amount;
    _notify();
  }
}
