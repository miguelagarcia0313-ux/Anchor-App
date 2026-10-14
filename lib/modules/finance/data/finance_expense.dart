import '../../../shared/trackable_entry.dart';

/// One expense as stored in Firestore at `users/{uid}/expenses/{id}`.
///
/// Two writers produce these documents:
///   * Cloud Functions `syncTransactions` (source: "plaid") -- one doc per
///     Plaid transaction, doc id = Plaid transaction_id.
///   * The app's Add Expense form (source: "manual").
///
/// The Finance screen and the insights math don't care which one it came
/// from: [toTrackableEntry] turns either into the shared model, so
/// `calculateBudgetPace()` and `calculateSavingsProjection()` work
/// unchanged on real data.
class FinanceExpense {
  const FinanceExpense({
    required this.id,
    required this.amount,
    required this.date,
    required this.autoCategory,
    required this.source,
    this.userCategory,
    this.merchantName,
    this.pending = false,
  });

  final String id;

  /// Positive = money spent (Plaid's sign convention).
  final double amount;

  /// The transaction date (Plaid gives a calendar date, no time).
  final DateTime date;

  /// Category picked automatically (by `categorize.ts`, or by the user in
  /// the manual-entry form).
  final String autoCategory;

  /// The user's override from the re-categorize sheet, if any.
  final String? userCategory;

  final String? merchantName;
  final bool pending;

  /// "plaid" or "manual".
  final String source;

  /// The category everything else should use: the user's choice wins.
  String get category => userCategory ?? autoCategory;

  bool get isManual => source == 'manual';

  /// Builds an expense from a Firestore document's data.
  ///
  /// Defensive on purpose: Firestore has no schema, so a missing or
  /// wrongly-typed field falls back to a safe value instead of crashing
  /// the whole Finance screen.
  factory FinanceExpense.fromMap(String id, Map<String, dynamic> map) {
    final rawAmount = map['amount'];
    final rawDate = map['date'];
    return FinanceExpense(
      id: id,
      amount: rawAmount is num ? rawAmount.toDouble() : 0.0,
      date: (rawDate is String ? DateTime.tryParse(rawDate) : null) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      autoCategory: (map['autoCategory'] as String?) ?? 'miscellaneous',
      userCategory: map['userCategory'] as String?,
      merchantName: map['merchantName'] as String?,
      pending: (map['pending'] as bool?) ?? false,
      source: (map['source'] as String?) ?? 'plaid',
    );
  }

  /// Shape written by the app for a manual expense. Must stay in sync with
  /// the `allow create` rule in firestore.rules (same keys, same types).
  static Map<String, dynamic> manualMap({
    required double amount,
    required DateTime date,
    required String category,
    String? note,
  }) {
    return {
      'amount': amount,
      'date': formatDate(date),
      'merchantName': (note == null || note.trim().isEmpty) ? null : note.trim(),
      'autoCategory': category,
      'source': 'manual',
      'pending': false,
    };
  }

  /// "2026-10-08" -- the same format Plaid uses for `date`.
  static String formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  TrackableEntry toTrackableEntry() {
    return TrackableEntry(
      id: id,
      moduleType: 'finance',
      category: category,
      value: amount,
      timestamp: date,
      note: merchantName,
      source: source,
    );
  }
}

/// Connection status the Cloud Functions write to
/// `users/{uid}/settings/finance` under `bank`. Contains no secrets.
class BankStatus {
  const BankStatus({
    this.connected = false,
    this.institutionName,
    this.lastSyncedAt,
  });

  final bool connected;
  final String? institutionName;
  final DateTime? lastSyncedAt;

  static const disconnected = BankStatus();
}

/// Everything the Finance screen needs in one snapshot.
class FinanceSnapshot {
  const FinanceSnapshot({
    required this.expenses,
    required this.budgets,
    required this.bank,
  });

  final List<FinanceExpense> expenses;
  final Map<String, double> budgets;
  final BankStatus bank;

  List<TrackableEntry> get entries =>
      expenses.map((e) => e.toTrackableEntry()).toList();
}
