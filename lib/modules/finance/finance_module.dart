import 'package:flutter/material.dart';
import '../../shared/anchor_module.dart';
import '../../shared/trackable_entry.dart';
import '../insights/mock_data.dart';
import '../insights/insights_calculations.dart';
import 'manual_entry_form.dart' show manualCategoryDisplayName, ManualEntryForm;

/// DEMO WIRING: uses mock data + the insights calculations directly.
/// Once persistence (drift) exists, swap generateMockEntries() for a real
/// data read -- everything else here stays the same, since it only
/// depends on getting a List<TrackableEntry> from somewhere.
///
/// Also note: category budgets ($150 groceries, etc.) aren't part of the
/// shared TrackableEntry model -- there's no field for "my grocery budget
/// is $150" anywhere yet. This demo hardcodes them in _demoBudgets below.
///
/// WIDGET KEYS: added for BDD automation (Appium + appium_flutter_finder).
/// These three names are load-bearing -- they match locators already
/// written in features/steps/finance_steps.py:
///   `finance_summary_card`               -- on the dashboard card, so
///                                            Appium can tap into Finance
///   `finance_category_row_<category>`    -- one per category row
///   `finance_category_amount_<category>` -- the "$X / $Y ... ahead of pace"
///                                            text Appium reads assertions from
/// If any of these three literal strings change here, the matching
/// locator in finance_steps.py has to change too, or the step silently
/// stops finding its element.
///
/// MANUAL ENTRY: entries logged via the "+ Add Expense" button are held
/// in _FinanceDetailScreenState's session state only -- no persistence
/// layer exists yet (see generateMockEntries() above), so these are lost
/// on app restart. This is a deliberate, temporary stopgap, not a design
/// decision to leave permanently. Manual entry categories (see
/// manual_entry_form.dart) now match _demoBudgets' keys exactly, so every
/// manual entry counts toward its category's pace ring below -- there's
/// no "uncategorized" fallback case anymore.
///
/// "miscellaneous" budget ($50/mo) is a placeholder, same reasoning as
/// the other hardcoded budgets: there's no per-user budget configuration
/// yet. Change the number directly here until that exists.

const _demoBudgets = {
  'groceries': 150.0,
  'eating_out': 100.0,
  'subscriptions': 30.0,
  'entertainment': 50.0,
  'miscellaneous': 50.0,
};

class FinanceModule implements AnchorModule {
  @override
  String get id => 'finance';

  @override
  String get displayName => 'Finance';

  @override
  Widget buildSummaryCard(BuildContext context) {
    final entries = generateMockEntries();
    final categories = _demoBudgets.keys.toList();

    return Card(
      key: const Key('finance_summary_card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Finance', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...categories.take(2).map((category) {
              final pace = calculateBudgetPace(
                entries: entries,
                category: category,
                monthlyBudget: _demoBudgets[category]!,
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${manualCategoryDisplayName(category)}: \$${pace.spent.toStringAsFixed(0)} / \$${pace.monthlyBudget.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: pace.isOverPace ? Colors.red[700] : Colors.black87,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget buildDetailView(BuildContext context) {
    return const _FinanceDetailScreen();
  }
}

class _FinanceDetailScreen extends StatefulWidget {
  const _FinanceDetailScreen();

  @override
  State<_FinanceDetailScreen> createState() => _FinanceDetailScreenState();
}

class _FinanceDetailScreenState extends State<_FinanceDetailScreen> {
  final List<TrackableEntry> _manualEntries = [];

  List<TrackableEntry> get _allEntries => [
        ...generateMockEntries(),
        ..._manualEntries,
      ];

  void _openManualEntryForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => ManualEntryForm(
        onSubmit: (entry) {
          setState(() => _manualEntries.add(entry));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _allEntries;
    final categories = _demoBudgets.keys.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Finance')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('manual_entry_fab'),
        onPressed: _openManualEntryForm,
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...categories.map((category) {
            final pace = calculateBudgetPace(
              entries: entries,
              category: category,
              monthlyBudget: _demoBudgets[category]!,
            );
            final ratio = (pace.spent / pace.monthlyBudget).clamp(0.0, 1.0);

            return Card(
              key: Key('finance_category_row_$category'),
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: ratio,
                        strokeWidth: 4,
                        color: pace.isOverPace ? Colors.red : Colors.blue,
                        backgroundColor: Colors.grey[300],
                      ),
                    ],
                  ),
                ),
                title: Text(manualCategoryDisplayName(category)),
                subtitle: Text(
                  key: Key('finance_category_amount_$category'),
                  '\$${pace.spent.toStringAsFixed(2)} / \$${pace.monthlyBudget.toStringAsFixed(2)}'
                  '${pace.isOverPace ? "  •  ahead of pace" : ""}',
                ),
              ),
            );
          }),
          if (_manualEntries.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Manual Entries',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ..._manualEntries.map((entry) => Card(
                  key: Key('manual_entry_row_${entry.id}'),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(manualCategoryDisplayName(entry.category)),
                    subtitle: entry.note != null ? Text(entry.note!) : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('\$${entry.value!.toStringAsFixed(2)}'),
                        IconButton(
                          key: Key('manual_entry_delete_${entry.id}'),
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove entry',
                          onPressed: () {
                            setState(() => _manualEntries.remove(entry));
                          },
                        ),
                      ],
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}