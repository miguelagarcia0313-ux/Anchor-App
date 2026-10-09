import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:plaid_flutter/plaid_flutter.dart';

/// Result of one `syncTransactions` call.
class SyncResult {
  const SyncResult({
    required this.saved,
    required this.skipped,
    required this.removed,
    required this.updateStatus,
  });

  final int saved;
  final int skipped;
  final int removed;

  /// Plaid's `transactions_update_status`. "NOT_READY" right after linking
  /// a sandbox bank means "history is still being generated, try again".
  final String updateStatus;

  bool get notReady => updateStatus == 'NOT_READY';
}

/// What happened when the user went through Plaid Link.
sealed class ConnectOutcome {
  const ConnectOutcome();
}

class ConnectSucceeded extends ConnectOutcome {
  const ConnectSucceeded({this.institutionName, required this.firstSync});
  final String? institutionName;
  final SyncResult firstSync;
}

class ConnectCancelled extends ConnectOutcome {
  const ConnectCancelled();
}

class ConnectFailed extends ConnectOutcome {
  const ConnectFailed(this.message);
  final String message;
}

/// The bank-connection actions the Finance screen needs.
///
/// An interface so widget tests can use a fake (Plaid Link is a native
/// SDK and Cloud Functions need a real Firebase project -- neither runs
/// inside `flutter test`).
abstract class BankConnector {
  Future<ConnectOutcome> connect();
  Future<SyncResult> sync();
}

/// Real implementation:
///   1. createLinkToken (Cloud Function)   -> link_token
///   2. Plaid Link UI (native SDK)          -> public_token
///   3. exchangePublicToken (Cloud Function) -> access_token stays on server
///   4. syncTransactions (Cloud Function)   -> expenses land in Firestore
///
/// The app never sees the Plaid secret or the access_token. Step 4 writes
/// to Firestore, and the Finance screen updates because it is *watching*
/// Firestore -- this class doesn't hand transactions to the UI at all.
class PlaidBankConnector implements BankConnector {
  PlaidBankConnector({
    FirebaseFunctions? functions,
    this.notReadyRetries = 6,
    this.retryDelay = const Duration(seconds: 3),
  }) : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// Sandbox needs a few seconds to generate fake history after linking.
  final int notReadyRetries;
  final Duration retryDelay;

  @override
  Future<ConnectOutcome> connect() async {
    try {
      final tokenResult =
          await _functions.httpsCallable('createLinkToken').call<dynamic>();
      final linkToken = (tokenResult.data as Map)['linkToken'] as String;

      final linkResult = await _runPlaidLink(linkToken);
      if (linkResult == null) return const ConnectCancelled();

      final institution = linkResult.metadata.institution?.name;
      await _functions.httpsCallable('exchangePublicToken').call<dynamic>({
        'publicToken': linkResult.publicToken,
        'institutionName': institution,
      });

      final first = await _syncUntilReady();
      return ConnectSucceeded(institutionName: institution, firstSync: first);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Plaid connect failed: ${e.code} ${e.message}');
      return ConnectFailed(_friendlyFunctionsError(e));
    } catch (e) {
      debugPrint('Plaid connect failed: $e');
      return ConnectFailed('Could not connect to the bank. ($e)');
    }
  }

  @override
  Future<SyncResult> sync() => _callSync();

  Future<SyncResult> _callSync() async {
    final result =
        await _functions.httpsCallable('syncTransactions').call<dynamic>();
    final data = Map<String, dynamic>.from(result.data as Map);
    return SyncResult(
      saved: (data['saved'] as num?)?.toInt() ?? 0,
      skipped: (data['skipped'] as num?)?.toInt() ?? 0,
      removed: (data['removed'] as num?)?.toInt() ?? 0,
      updateStatus: data['updateStatus'] as String? ?? 'UNKNOWN',
    );
  }

  /// Right after linking, sandbox often answers NOT_READY with zero
  /// transactions. Retry a few times so the demo doesn't show an empty
  /// screen and make it look broken.
  Future<SyncResult> _syncUntilReady() async {
    var result = await _callSync();
    for (var i = 0; i < notReadyRetries && result.notReady; i++) {
      await Future<void>.delayed(retryDelay);
      result = await _callSync();
    }
    return result;
  }

  /// Opens Plaid Link and waits for the user to finish.
  /// Returns null if they closed it without connecting.
  Future<LinkSuccess?> _runPlaidLink(String linkToken) async {
    final done = Completer<LinkSuccess?>();
    late final StreamSubscription<LinkSuccess> onSuccess;
    late final StreamSubscription<LinkExit> onExit;

    onSuccess = PlaidLink.onSuccess.listen((event) {
      if (!done.isCompleted) done.complete(event);
    });
    onExit = PlaidLink.onExit.listen((event) {
      if (event.error != null) {
        debugPrint('Plaid Link exit error: ${event.error?.description()}');
      }
      if (!done.isCompleted) done.complete(null);
    });

    try {
      await PlaidLink.create(
        configuration: LinkTokenConfiguration(token: linkToken),
      );
      await PlaidLink.open();
      return await done.future;
    } finally {
      await onSuccess.cancel();
      await onExit.cancel();
    }
  }

  static String _friendlyFunctionsError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return 'Please sign in again, then retry.';
      case 'not-found':
        return 'The Plaid Cloud Functions are not deployed yet.';
      case 'failed-precondition':
        return e.message ?? 'Connect a bank first.';
      default:
        return 'Bank connection error (${e.code}). Check the Functions logs.';
    }
  }
}
