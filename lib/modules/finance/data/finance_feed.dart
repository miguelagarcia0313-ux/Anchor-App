import 'dart:async';

import 'finance_expense.dart';

/// Shares one repository subscription between every widget that wants
/// finance data, and replays the latest snapshot to new listeners.
///
/// Why: a plain StreamBuilder on `repository.watch()` would open a new
/// Firestore listener on every rebuild, and a plain broadcast stream would
/// leave a newly opened screen blank until the *next* change.
class FinanceFeed {
  FinanceFeed(this._source);

  final Stream<FinanceSnapshot> Function() _source;
  StreamSubscription<FinanceSnapshot>? _sub;
  FinanceSnapshot? latest;
  Object? latestError;

  late final StreamController<FinanceSnapshot> _controller =
      StreamController<FinanceSnapshot>.broadcast(
    onListen: () {
      _sub ??= _source().listen(
        (value) {
          latest = value;
          latestError = null;
          _controller.add(value);
        },
        onError: (Object error, StackTrace stack) {
          latestError = error;
          _controller.addError(error, stack);
        },
      );
    },
    // Last listener left (e.g. signed out): stop the Firestore listener.
    onCancel: () async {
      // Clear the field BEFORE awaiting, so a listener that arrives while
      // the old subscription is still cancelling starts a fresh one.
      final old = _sub;
      _sub = null;
      await old?.cancel();
    },
  );

  Stream<FinanceSnapshot> get stream async* {
    final cached = latest;
    if (cached != null) yield cached;
    yield* _controller.stream;
  }
}
