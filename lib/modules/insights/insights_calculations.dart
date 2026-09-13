import '../../shared/trackable_entry.dart';
 
/// Data-analysis functions for the Insights role.
///
/// These take a list of [TrackableEntry] (mock or real, doesn't matter —
/// that's the point of building against the shared model) and produce the
/// numbers that either get shown directly or summarized into a prompt for
/// the Claude API insight.
 
/// How much has been spent in [category] since [since], and how that
/// compares to [monthlyBudget] pro-rated for the days elapsed so far.
class BudgetPace {
  final String category;
  final double spent;
  final double monthlyBudget;
  final double expectedSpendSoFar; // budget pro-rated to today's date
  final bool isOverPace;
 
  BudgetPace({
    required this.category,
    required this.spent,
    required this.monthlyBudget,
    required this.expectedSpendSoFar,
    required this.isOverPace,
  });
}
 
BudgetPace calculateBudgetPace({
  required List<TrackableEntry> entries,
  required String category,
  required double monthlyBudget,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final startOfMonth = DateTime(today.year, today.month, 1);
  final daysElapsed = today.difference(startOfMonth).inDays + 1;
  final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
 
  final spent = entries
      .where((e) =>
          e.moduleType == 'finance' &&
          e.category == category &&
          !e.timestamp.isBefore(startOfMonth))
      .fold<double>(0.0, (sum, e) => sum + (e.value ?? 0));
 
  final expectedSpendSoFar =
      monthlyBudget * (daysElapsed / daysInMonth);
 
  return BudgetPace(
    category: category,
    spent: spent,
    monthlyBudget: monthlyBudget,
    expectedSpendSoFar: expectedSpendSoFar,
    isOverPace: spent > expectedSpendSoFar,
  );
}
 
/// Projects what avoiding a set of "discretionary" categories for
/// [months] would be worth, based on recent average spend in those
/// categories.
///
/// NOTE: the shared TrackableEntry model doesn't have an `isDiscretionary`
/// flag (the original project doc mentions one on the Finance module's
/// data fields, but it's not on the shared model as committed). 
double calculateSavingsProjection({
  required List<TrackableEntry> entries,
  required List<String> discretionaryCategories,
  required int months,
  int lookbackDays = 30,
}) {
  final cutoff = DateTime.now().subtract(Duration(days: lookbackDays));
 
  final recentDiscretionarySpend = entries
      .where((e) =>
          e.moduleType == 'finance' &&
          discretionaryCategories.contains(e.category) &&
          e.timestamp.isAfter(cutoff))
      .fold<double>(0.0, (sum, e) => sum + (e.value ?? 0));
 
  // Normalize the lookback window to a monthly rate, then project forward.
  final monthlyRate = recentDiscretionarySpend * (30 / lookbackDays);
  return monthlyRate * months;
}
 
/// Simple task-completion pattern — the kind of thing that becomes a
/// nudge ("you've completed 40% of homework tasks this week") once the
/// Tasks module has real data.
double taskCompletionRate({
  required List<TrackableEntry> entries,
  String? category,
}) {
  final relevant = entries.where((e) =>
      e.moduleType == 'task' && (category == null || e.category == category));
 
  if (relevant.isEmpty) return 0.0;
 
  final completed = relevant.where((e) => e.isComplete).length;
  return completed / relevant.length;
}