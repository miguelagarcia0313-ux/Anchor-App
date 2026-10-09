import 'package:flutter/material.dart';

import '../insights/insights_calculations.dart';
import 'category_detail_screen.dart';
import 'data/finance_expense.dart';
import 'data/finance_feed.dart';
import 'data/finance_repository.dart';
import 'finance_widgets.dart';
import 'manual_entry_form.dart';
import 'plaid/plaid_service.dart';

/// Full Finance screen: bank connection, category budget rings, savings
/// projection, and recent transactions. All data is live from [feed].
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({
    super.key,
    required this.feed,
    required this.repository,
    required this.connector,
  });

  final FinanceFeed feed;
  final FinanceRepository repository;
  final BankConnector connector;

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  // Created once, so rebuilding this screen doesn't resubscribe.
  late final Stream<FinanceSnapshot> _stream = widget.feed.stream;
  bool _bankBusy = false;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _connectBank() async {
    setState(() => _bankBusy = true);
    final outcome = await widget.connector.connect();
    if (!mounted) return;
    setState(() => _bankBusy = false);
    switch (outcome) {
      case ConnectSucceeded(:final institutionName, :final firstSync):
        final bank = institutionName ?? 'your bank';
        _snack(firstSync.notReady
            ? 'Linked $bank. Transactions are still being prepared -- tap Sync in a moment.'
            : 'Linked $bank and imported ${firstSync.saved} transactions.');
      case ConnectCancelled():
        break;
      case ConnectFailed(:final message):
        _snack(message);
    }
  }

  Future<void> _sync() async {
    setState(() => _bankBusy = true);
    try {
      final result = await widget.connector.sync();
      _snack(result.notReady
          ? 'Bank is still preparing transactions. Try again shortly.'
          : 'Synced: ${result.saved} updated, ${result.removed} removed.');
    } catch (e) {
      _snack('Sync failed: $e');
    } finally {
      if (mounted) setState(() => _bankBusy = false);
    }
  }

  void _openManualEntryForm() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => ManualEntryForm(
        onSubmit: (entry) async {
          try {
            await widget.repository.addManualExpense(
              amount: entry.value!,
              category: entry.category,
              date: entry.timestamp,
              note: entry.note,
            );
          } catch (e) {
            _snack('Could not save expense: $e');
          }
        },
      ),
    );
  }

  Future<void> _deleteManual(FinanceExpense expense) async {
    try {
      await widget.repository.deleteManualExpense(expense.id);
    } catch (e) {
      _snack('Could not delete: $e');
    }
  }

  Future<void> _recategorize(FinanceExpense expense) async {
    final picked = await showCategoryPicker(context, expense);
    if (picked == null || picked == expense.category) return;
    try {
      await widget.repository.setUserCategory(expense.id, picked);
    } catch (e) {
      _snack('Could not change category: $e');
    }
  }

  void _openCategory(String category) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CategoryDetailScreen(
        category: category,
        feed: widget.feed,
        repository: widget.repository,
        onRecategorize: _recategorize,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finance')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('manual_entry_fab'),
        onPressed: _openManualEntryForm,
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
      body: StreamBuilder<FinanceSnapshot>(
        stream: _stream,
        initialData: widget.feed.latest,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  "Couldn't load finance data.\n${snap.error}",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildBody(snap.data!);
        },
      ),
    );
  }

  Widget _buildBody(FinanceSnapshot data) {
    final entries = data.entries;
    final recent = data.expenses.take(15).toList();

    return ListView(
      // Bottom padding so the FAB doesn't cover the last row.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        BankCard(
          status: data.bank,
          busy: _bankBusy,
          onConnect: _connectBank,
          onSync: _sync,
        ),
        const SizedBox(height: 16),
        const SectionTitle('This month'),
        ...data.budgets.keys.map((category) {
          final pace = calculateBudgetPace(
            entries: entries,
            category: category,
            monthlyBudget: data.budgets[category]!,
          );
          return CategoryPaceRow(
            category: category,
            pace: pace,
            onTap: () => _openCategory(category),
          );
        }),
        const SizedBox(height: 8),
        SavingsProjectionCard(entries: entries),
        const SizedBox(height: 16),
        const SectionTitle('Recent transactions'),
        if (recent.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No transactions yet. Connect a bank or tap Add Expense.',
              key: Key('finance_empty_state'),
              textAlign: TextAlign.center,
            ),
          )
        else
          ...recent.map((expense) => ExpenseTile(
                expense: expense,
                onTap: () => _recategorize(expense),
                onDelete:
                    expense.isManual ? () => _deleteManual(expense) : null,
              )),
      ],
    );
  }
}
