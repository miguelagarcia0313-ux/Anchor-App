import 'package:anchor_app/modules/finance/data/finance_expense.dart';
import 'package:anchor_app/modules/finance/data/finance_repository.dart';
import 'package:anchor_app/modules/finance/finance_module.dart';
import 'package:anchor_app/modules/finance/plaid/plaid_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for Plaid + Cloud Functions: "connecting" just drops two
/// bank transactions into the in-memory repository, the same way
/// syncTransactions drops them into Firestore in the real app.
class FakeBankConnector implements BankConnector {
  FakeBankConnector(this.repo);

  final InMemoryFinanceRepository repo;
  int syncCalls = 0;

  @override
  Future<ConnectOutcome> connect() async {
    final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
    repo.importFromBank([
      FinanceExpense(
        id: 'tx_1',
        amount: 12.5,
        date: monthStart,
        autoCategory: 'eating_out',
        merchantName: "McDonald's",
        source: 'plaid',
      ),
      FinanceExpense(
        id: 'tx_2',
        amount: 15.99,
        date: monthStart,
        autoCategory: 'subscriptions',
        merchantName: 'Spotify',
        source: 'plaid',
      ),
    ], institution: 'First Platypus Bank');
    return const ConnectSucceeded(
      institutionName: 'First Platypus Bank',
      firstSync: SyncResult(
        saved: 2,
        skipped: 0,
        removed: 0,
        updateStatus: 'COMPLETE',
      ),
    );
  }

  @override
  Future<SyncResult> sync() async {
    syncCalls++;
    return const SyncResult(
      saved: 0,
      skipped: 0,
      removed: 0,
      updateStatus: 'COMPLETE',
    );
  }
}

void main() {
  group('FinanceExpense.fromMap', () {
    test('reads a Plaid document written by syncTransactions', () {
      final e = FinanceExpense.fromMap('tx_abc', {
        'amount': 89.4,
        'date': '2026-10-03',
        'merchantName': 'H-E-B',
        'plaidCategory': 'FOOD_AND_DRINK_GROCERIES',
        'autoCategory': 'groceries',
        'pending': false,
        'source': 'plaid',
      });
      expect(e.amount, 89.4);
      expect(e.date, DateTime(2026, 10, 3));
      expect(e.category, 'groceries');
      expect(e.isManual, isFalse);
    });

    test("the user's category wins over the automatic one", () {
      final e = FinanceExpense.fromMap('tx_1', {
        'amount': 20,
        'date': '2026-10-01',
        'autoCategory': 'miscellaneous',
        'userCategory': 'entertainment',
        'source': 'plaid',
      });
      expect(e.category, 'entertainment');
      expect(e.toTrackableEntry().category, 'entertainment');
    });

    test('integer amounts from Firestore become doubles', () {
      final e = FinanceExpense.fromMap('m1', {
        'amount': 20,
        'date': '2026-10-01',
        'autoCategory': 'groceries',
        'source': 'manual',
      });
      expect(e.amount, 20.0);
      expect(e.isManual, isTrue);
    });

    test('missing or junk fields do not crash', () {
      final e = FinanceExpense.fromMap('bad', {'amount': 'lots', 'date': 7});
      expect(e.amount, 0.0);
      expect(e.category, 'miscellaneous');
    });

    test('manualMap matches the shape firestore.rules allows', () {
      final map = FinanceExpense.manualMap(
        amount: 9.99,
        date: DateTime(2026, 1, 5),
        category: 'groceries',
        note: '  milk  ',
      );
      expect(map.keys.toSet(), {
        'amount', 'date', 'merchantName', 'autoCategory', 'source', 'pending',
      });
      expect(map['date'], '2026-01-05');
      expect(map['merchantName'], 'milk');
      expect(map['source'], 'manual');
    });
  });

  group('parseBudgets', () {
    test('falls back to defaults', () {
      expect(parseBudgets(null), defaultBudgets);
    });

    test('saved values override defaults; junk is ignored', () {
      final b = parseBudgets({
        'groceries': 200,
        'eating_out': -5,
        'not_a_category': 999,
      });
      expect(b['groceries'], 200.0);
      expect(b['eating_out'], defaultBudgets['eating_out']);
      expect(b.containsKey('not_a_category'), isFalse);
    });
  });

  test('combineLatest2 waits for both streams, then follows either', () async {
    final out = combineLatest2(
      Stream.fromIterable([1, 2]),
      Stream.value('a'),
      (int n, String s) => '$s$n',
    );
    expect(await out.toList(), containsAllInOrder(['a2']));
  });

  group('Finance screen (in-memory data, fake bank)', () {
    late InMemoryFinanceRepository repo;
    late FakeBankConnector bank;
    late FinanceModule module;

    setUp(() {
      final monthStart =
          DateTime(DateTime.now().year, DateTime.now().month, 1);
      repo = InMemoryFinanceRepository(expenses: [
        FinanceExpense(
          id: 'm1',
          amount: 62.40,
          date: monthStart,
          autoCategory: 'groceries',
          merchantName: 'H-E-B run',
          source: 'manual',
        ),
      ]);
      bank = FakeBankConnector(repo);
      module = FinanceModule(repository: repo, connector: bank);
    });

    Future<void> pumpFinance(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: module.buildDetailView),
      ));
      await tester.pumpAndSettle();
    }

    String amountText(WidgetTester tester, String category) {
      final widget = tester.widget<Text>(
        find.byKey(Key('finance_category_amount_$category')),
      );
      return widget.data!;
    }

    testWidgets('shows stored data with the BDD key/text format',
        (tester) async {
      await pumpFinance(tester);
      expect(amountText(tester, 'groceries'), startsWith(r'$62.40 / $150.00'));
      expect(find.byKey(const Key('plaid_connect_button')), findsOneWidget);
      expect(find.byKey(const Key('manual_entry_row_m1')), findsOneWidget);
    });

    testWidgets('connecting a bank imports transactions into the rings',
        (tester) async {
      await pumpFinance(tester);
      await tester.tap(find.byKey(const Key('plaid_connect_button')));
      await tester.pumpAndSettle();

      expect(find.text('First Platypus Bank'), findsOneWidget);
      expect(find.byKey(const Key('expense_row_tx_1')), findsOneWidget);
      expect(amountText(tester, 'eating_out'), startsWith(r'$12.50 / $100.00'));
      expect(
        amountText(tester, 'subscriptions'),
        startsWith(r'$15.99 / $30.00'),
      );

      await tester.tap(find.byKey(const Key('plaid_sync_button')));
      await tester.pumpAndSettle();
      expect(bank.syncCalls, 1);
    });

    testWidgets('re-categorizing a bank transaction moves its amount',
        (tester) async {
      await pumpFinance(tester);
      await tester.tap(find.byKey(const Key('plaid_connect_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('expense_row_tx_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category_option_entertainment')));
      await tester.pumpAndSettle();

      expect(amountText(tester, 'eating_out'), startsWith(r'$0.00'));
      expect(amountText(tester, 'entertainment'), startsWith(r'$12.50'));
    });

    testWidgets('manual expenses can be deleted', (tester) async {
      await pumpFinance(tester);
      await tester.tap(find.byKey(const Key('manual_entry_delete_m1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('manual_entry_row_m1')), findsNothing);
      expect(amountText(tester, 'groceries'), startsWith(r'$0.00'));
    });

    testWidgets('summary card reads the same live data', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: module.buildSummaryCard)),
      ));
      await tester.pumpAndSettle();
      expect(find.text(r'Groceries: $62 / $150'), findsOneWidget);
      expect(find.text('No bank connected'), findsOneWidget);
    });
  });
}
