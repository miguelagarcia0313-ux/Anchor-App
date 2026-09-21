import 'package:flutter/material.dart';
import '../../shared/anchor_module.dart';
import '../insights/mock_data.dart';
import '../insights/insights_calculations.dart';
 
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
///   finance_summary_card               -- on the dashboard card, so
///                                          Appium can tap into Finance
///   finance_category_row_<category>    -- one per category row
///   finance_category_amount_<category> -- the "$X / $Y ... ahead of pace"
///                                          text Appium reads assertions from
/// If any of these three literal strings change here, the matching
/// locator in finance_steps.py has to change too, or the step silently
/// stops finding its element.
 
const _demoBudgets = {
  'groceries': 150.0,
  'eating_out': 100.0,
  'subscriptions': 30.0,
  'entertainment': 50.0,
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
                  '${_displayName(category)}: \$${pace.spent.toStringAsFixed(0)} / \$${pace.monthlyBudget.toStringAsFixed(0)}',
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
    final entries = generateMockEntries();
    final categories = _demoBudgets.keys.toList();
 
    return Scaffold(
      appBar: AppBar(title: const Text('Finance')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
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
              title: Text(_displayName(category)),
              subtitle: Text(
                key: Key('finance_category_amount_$category'),
                '\$${pace.spent.toStringAsFixed(2)} / \$${pace.monthlyBudget.toStringAsFixed(2)}'
                '${pace.isOverPace ? "  •  ahead of pace" : ""}',
              ),
            ),
          );
        },
      ),
    );
  }
 
  String _displayName(String category) {
    switch (category) {
      case 'eating_out':
        return 'Eating Out';
      case 'groceries':
        return 'Groceries';
      case 'subscriptions':
        return 'Subscriptions';
      case 'entertainment':
        return 'Entertainment';
      default:
        return category;
    }
  }
}
 