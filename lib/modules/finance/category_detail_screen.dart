import 'package:flutter/material.dart';

import '../insights/insights_calculations.dart';
import 'data/finance_expense.dart';
import 'data/finance_feed.dart';
import 'data/finance_repository.dart';
import 'finance_widgets.dart';
import 'manual_entry_form.dart' show manualCategoryDisplayName;

/// "Eating Out" detail screen from the wireframe: big ring, spent vs
/// budget, an editable budget, and this month's transactions.
class CategoryDetailScreen extends StatefulWidget {
  const CategoryDetailScreen({
    super.key,
    required this.category,
    required this.feed,
    required this.repository,
    required this.onRecategorize,
  });

  final String category;
  final FinanceFeed feed;
  final FinanceRepository repository;
  final Future<void> Function(FinanceExpense) onRecategorize;

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  late final Stream<FinanceSnapshot> _stream = widget.feed.stream;

  Future<void> _editBudget(double current) async {
    final result = await showDialog<double>(
      context: context,
      builder: (_) => _BudgetDialog(
        title: '${manualCategoryDisplayName(widget.category)} budget',
        initial: current,
      ),
    );
    if (result == null) return;
    try {
      await widget.repository.setBudget(widget.category, result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save budget: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = manualCategoryDisplayName(widget.category);
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: StreamBuilder<FinanceSnapshot>(
        stream: _stream,
        initialData: widget.feed.latest,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          final budget = data.budgets[widget.category] ?? 0.0;
          final pace = calculateBudgetPace(
            entries: data.entries,
            category: widget.category,
            monthlyBudget: budget,
          );
          final now = DateTime.now();
          final monthStart = DateTime(now.year, now.month, 1);
          final thisMonth = data.expenses
              .where((e) =>
                  e.category == widget.category && !e.date.isBefore(monthStart))
              .toList();
          final ratio =
              budget <= 0 ? 0.0 : (pace.spent / budget).clamp(0.0, 1.0);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: CircularProgressIndicator(
                      value: ratio,
                      strokeWidth: 8,
                      color: pace.isOverPace ? Colors.red : Colors.blue,
                      backgroundColor: Colors.grey[300],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '\$${pace.spent.toStringAsFixed(2)}',
                          key: Key('category_detail_spent_${widget.category}'),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text('of \$${budget.toStringAsFixed(2)} this month'),
                        Text(
                          'Expected by today: '
                          '\$${pace.expectedSpendSoFar.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: pace.isOverPace
                                ? Colors.red[700]
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('budget_edit_button'),
                  onPressed: () => _editBudget(budget),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit budget'),
                ),
              ),
              const SizedBox(height: 16),
              const SectionTitle('This month'),
              if (thisMonth.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Nothing in this category this month.'),
                )
              else
                ...thisMonth.map((e) => ExpenseTile(
                      expense: e,
                      onTap: () => widget.onRecategorize(e),
                    )),
            ],
          );
        },
      ),
    );
  }
}

/// Owns its TextEditingController so it's disposed with the dialog, not
/// while the dialog is still animating closed.
class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.title, required this.initial});

  final String title;
  final double initial;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial.toStringAsFixed(0));
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter an amount greater than \$0');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('budget_edit_field'),
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          prefixText: '\$',
          suffixText: 'per month',
          errorText: _error,
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('budget_save_button'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
