import 'package:flutter/material.dart';

import '../../shared/trackable_entry.dart';
import '../insights/insights_calculations.dart';
import 'data/finance_expense.dart';
import 'manual_entry_form.dart'
    show manualCategoryDisplayName, manualEntryCategories;

IconData categoryIcon(String category) {
  switch (category) {
    case 'groceries':
      return Icons.local_grocery_store_outlined;
    case 'eating_out':
      return Icons.restaurant_outlined;
    case 'subscriptions':
      return Icons.subscriptions_outlined;
    case 'entertainment':
      return Icons.movie_outlined;
    default:
      return Icons.receipt_long_outlined;
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Oct 8"
String shortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

/// "just now", "5 min ago", "3 h ago", "Oct 8"
String timeAgo(DateTime t, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  return shortDate(t);
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// Connect / sync card at the top of the Finance screen.
class BankCard extends StatelessWidget {
  const BankCard({
    super.key,
    required this.status,
    required this.busy,
    required this.onConnect,
    required this.onSync,
  });

  final BankStatus status;
  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    const spinner = SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );

    if (!status.connected) {
      return Card(
        key: const Key('plaid_bank_card'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Import transactions automatically',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Connect a bank through Plaid (Sandbox -- test data only).',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('plaid_connect_button'),
                onPressed: busy ? null : onConnect,
                icon: busy ? spinner : const Icon(Icons.account_balance),
                label: Text(busy ? 'Connecting…' : 'Connect bank'),
              ),
            ],
          ),
        ),
      );
    }

    final synced = status.lastSyncedAt;
    return Card(
      key: const Key('plaid_bank_card'),
      child: ListTile(
        leading: const Icon(Icons.account_balance),
        title: Text(status.institutionName ?? 'Bank connected'),
        subtitle: Text(
          synced == null ? 'Not synced yet' : 'Synced ${timeAgo(synced)}',
          key: const Key('plaid_last_synced'),
        ),
        trailing: busy
            ? spinner
            : IconButton(
                key: const Key('plaid_sync_button'),
                tooltip: 'Sync now',
                icon: const Icon(Icons.sync),
                onPressed: onSync,
              ),
      ),
    );
  }
}

/// One budget ring row. Keys and the amount text format are what the BDD
/// steps read -- change them together with features/steps/finance_steps.py.
class CategoryPaceRow extends StatelessWidget {
  const CategoryPaceRow({
    super.key,
    required this.category,
    required this.pace,
    this.onTap,
  });

  final String category;
  final BudgetPace pace;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = pace.monthlyBudget <= 0
        ? 0.0
        : (pace.spent / pace.monthlyBudget).clamp(0.0, 1.0);

    return Card(
      key: Key('finance_category_row_$category'),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
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
              Icon(categoryIcon(category), size: 16),
            ],
          ),
        ),
        title: Text(manualCategoryDisplayName(category)),
        subtitle: Text(
          key: Key('finance_category_amount_$category'),
          '\$${pace.spent.toStringAsFixed(2)} / \$${pace.monthlyBudget.toStringAsFixed(2)}'
          '${pace.isOverPace ? "  •  ahead of pace" : ""}',
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// "If you cut ___ for ___ months, you'd save $___" -- from the wireframe,
/// powered by calculateSavingsProjection() on real data.
///
/// Discretionary is flagged per CATEGORY (team decision), so the user picks
/// categories here rather than marking individual expenses.
class SavingsProjectionCard extends StatefulWidget {
  const SavingsProjectionCard({super.key, required this.entries});
  final List<TrackableEntry> entries;

  @override
  State<SavingsProjectionCard> createState() => _SavingsProjectionCardState();
}

class _SavingsProjectionCardState extends State<SavingsProjectionCard> {
  final Set<String> _cut = {'eating_out', 'entertainment'};
  int _months = 2;

  @override
  Widget build(BuildContext context) {
    final projected = calculateSavingsProjection(
      entries: widget.entries,
      discretionaryCategories: _cut.toList(),
      months: _months,
    );

    return Card(
      key: const Key('savings_projection_card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Savings projection',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text('If you cut:'),
            Wrap(
              spacing: 6,
              children: manualEntryCategories.map((c) {
                return FilterChip(
                  key: Key('savings_cut_$c'),
                  label: Text(manualCategoryDisplayName(c)),
                  selected: _cut.contains(c),
                  onSelected: (on) => setState(() {
                    if (on) {
                      _cut.add(c);
                    } else {
                      _cut.remove(c);
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('For '),
                DropdownButton<int>(
                  key: const Key('savings_months_dropdown'),
                  value: _months,
                  items: const [1, 2, 3, 6, 12]
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text('$m month${m == 1 ? '' : 's'}'),
                          ))
                      .toList(),
                  onChanged: (m) => setState(() => _months = m ?? _months),
                ),
              ],
            ),
            Text(
              '\$${projected.toStringAsFixed(2)}',
              key: const Key('savings_projection_amount'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              'Based on your last 30 days of spending.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

class ExpenseTile extends StatelessWidget {
  const ExpenseTile({
    super.key,
    required this.expense,
    this.onTap,
    this.onDelete,
  });

  final FinanceExpense expense;
  final VoidCallback? onTap;

  /// Only passed for manual expenses (bank data can't be deleted).
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final details = [
      shortDate(expense.date),
      manualCategoryDisplayName(expense.category),
      expense.isManual ? 'Manual' : 'Bank',
      if (expense.pending) 'Pending',
      if (expense.userCategory != null) 'Edited',
    ].join(' · ');

    return Card(
      key: Key(expense.isManual
          ? 'manual_entry_row_${expense.id}'
          : 'expense_row_${expense.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(child: Icon(categoryIcon(expense.category))),
        title: Text(
          expense.merchantName ?? manualCategoryDisplayName(expense.category),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(details),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('\$${expense.amount.toStringAsFixed(2)}'),
            if (onDelete != null)
              IconButton(
                key: Key('manual_entry_delete_${expense.id}'),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove entry',
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for re-categorizing one expense. Returns the picked
/// category, or null if dismissed.
Future<String?> showCategoryPicker(
  BuildContext context,
  FinanceExpense expense,
) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Category for ${expense.merchantName ?? 'this expense'}',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          if (!expense.isManual)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Auto-detected: ${manualCategoryDisplayName(expense.autoCategory)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
          ...manualEntryCategories.map((c) => ListTile(
                key: Key('category_option_$c'),
                leading: Icon(categoryIcon(c)),
                title: Text(manualCategoryDisplayName(c)),
                trailing: c == expense.category
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(c),
              )),
        ],
      ),
    ),
  );
}
