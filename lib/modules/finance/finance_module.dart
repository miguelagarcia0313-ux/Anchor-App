import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../shared/anchor_module.dart';
import '../insights/insights_calculations.dart';
import 'data/finance_expense.dart';
import 'data/finance_feed.dart';
import 'data/finance_repository.dart';
import 'finance_screen.dart';
import 'manual_entry_form.dart' show manualCategoryDisplayName;
import 'plaid/plaid_service.dart';

/// Finance module: budgets, bank import (Plaid Sandbox), manual expenses.
///
/// DATA: no more mock data. Everything comes from a [FinanceRepository]:
///   * the real app uses [FirestoreFinanceRepository] for the signed-in
///     user (`users/{uid}/expenses` + `users/{uid}/settings/finance`);
///   * tests pass an [InMemoryFinanceRepository] with exact values.
/// Bank transactions are written to Firestore by Cloud Functions
/// (functions/src/plaid.ts); this module just watches Firestore.
///
/// WIDGET KEYS (load-bearing for features/steps/finance_steps.py):
///   `finance_summary_card`, `finance_category_row_<category>`,
///   `finance_category_amount_<category>` -- same names and text format
///   as before, so the existing BDD locators keep working.
class FinanceModule implements AnchorModule {
  FinanceModule({FinanceRepository? repository, BankConnector? connector})
      : _repositoryOverride = repository,
        _connectorOverride = connector;

  final FinanceRepository? _repositoryOverride;
  final BankConnector? _connectorOverride;

  late final FinanceRepository repository =
      _repositoryOverride ?? _repositoryForCurrentUser();

  late final BankConnector connector =
      _connectorOverride ?? PlaidBankConnector();

  /// One shared live feed for the dashboard card and the Finance screen.
  late final FinanceFeed feed = FinanceFeed(repository.watch);

  static FinanceRepository _repositoryForCurrentUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // The dashboard is behind AuthGate, so uid should always exist. If it
    // somehow doesn't, show an empty screen instead of crashing.
    if (uid == null) return InMemoryFinanceRepository();
    return FirestoreFinanceRepository(uid: uid);
  }

  @override
  String get id => 'finance';

  @override
  String get displayName => 'Finance';

  @override
  Widget buildSummaryCard(BuildContext context) =>
      _FinanceSummaryCard(feed: feed);

  @override
  Widget buildDetailView(BuildContext context) {
    return FinanceScreen(
      feed: feed,
      repository: repository,
      connector: connector,
    );
  }
}

/// The dashboard card. Stateful only so it can hold ONE stream for its
/// lifetime -- otherwise every dashboard rebuild would resubscribe.
class _FinanceSummaryCard extends StatefulWidget {
  const _FinanceSummaryCard({required this.feed});
  final FinanceFeed feed;

  @override
  State<_FinanceSummaryCard> createState() => _FinanceSummaryCardState();
}

class _FinanceSummaryCardState extends State<_FinanceSummaryCard> {
  late final Stream<FinanceSnapshot> _stream = widget.feed.stream;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('finance_summary_card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: StreamBuilder<FinanceSnapshot>(
          stream: _stream,
          // Avoids a one-frame "Loading…" flash when the dashboard rebuilds.
          initialData: widget.feed.latest,
          builder: (context, snap) {
            final children = <Widget>[
              const Text(
                'Finance',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
            ];
            if (snap.hasError) {
              children.add(const Text(
                "Couldn't load finance data.",
                style: TextStyle(fontSize: 12),
              ));
            } else if (!snap.hasData) {
              children.add(
                const Text('Loading…', style: TextStyle(fontSize: 12)),
              );
            } else {
              final data = snap.data!;
              final entries = data.entries;
              for (final category in data.budgets.keys.take(2)) {
                final pace = calculateBudgetPace(
                  entries: entries,
                  category: category,
                  monthlyBudget: data.budgets[category]!,
                );
                children.add(Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${manualCategoryDisplayName(category)}: '
                    '\$${pace.spent.toStringAsFixed(0)} / '
                    '\$${pace.monthlyBudget.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: pace.isOverPace ? Colors.red[700] : null,
                    ),
                  ),
                ));
              }
              if (!data.bank.connected) {
                children.add(Text(
                  'No bank connected',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ));
              }
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            );
          },
        ),
      ),
    );
  }
}
