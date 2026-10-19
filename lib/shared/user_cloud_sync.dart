import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class UserCloudSync {
  UserCloudSync._(this.userId, this._firestore);

  final String userId;
  final FirebaseFirestore _firestore;

  static UserCloudSync? forCurrentUser({required String? userIdOverride}) {
    if (userIdOverride != null || Firebase.apps.isEmpty) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return UserCloudSync._(user.uid, FirebaseFirestore.instance);
  }

  CollectionReference<Map<String, dynamic>> records(
    String module,
    String collection,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('modules')
        .doc(module)
        .collection(collection);
  }

  DocumentReference<Map<String, dynamic>> moduleDocument(String module) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('modules')
        .doc(module);
  }

  Future<void> setModuleSettings(
    String module,
    String document,
    Map<String, dynamic> data,
  ) {
    return moduleDocument(module)
        .collection('settings')
        .doc(document)
        .set(data, SetOptions(merge: true));
  }

  Future<void> migrateLocalDataOnce(
    String module,
    Future<void> Function() migrate,
  ) async {
    final marker = moduleDocument(module)
        .collection('metadata')
        .doc('localDataMigration');
    if ((await marker.get()).exists) return;
    await migrate();
    await marker.set({'completedAt': FieldValue.serverTimestamp()});
  }

  Future<void> setRecords(
    String module,
    String collection,
    Iterable<MapEntry<String, Map<String, dynamic>>> records,
  ) async {
    var batch = _firestore.batch();
    var writeCount = 0;
    for (final record in records) {
      batch.set(this.records(module, collection).doc(record.key), record.value);
      writeCount++;
      if (writeCount == 450) {
        await batch.commit();
        batch = _firestore.batch();
        writeCount = 0;
      }
    }
    if (writeCount > 0) await batch.commit();
  }

  Future<void> replaceRecords(
    String module,
    String collection,
    Iterable<MapEntry<String, Map<String, dynamic>>> records,
  ) async {
    final reference = this.records(module, collection);
    final existing = await reference.get();
    final replacement = {
      for (final record in records) record.key: record.value,
    };
    var batch = _firestore.batch();
    var writeCount = 0;

    for (final document in existing.docs) {
      if (!replacement.containsKey(document.id)) {
        batch.delete(document.reference);
        writeCount++;
        if (writeCount == 450) {
          await batch.commit();
          batch = _firestore.batch();
          writeCount = 0;
        }
      }
    }
    for (final record in replacement.entries) {
      batch.set(reference.doc(record.key), record.value);
      writeCount++;
      if (writeCount == 450) {
        await batch.commit();
        batch = _firestore.batch();
        writeCount = 0;
      }
    }
    if (writeCount > 0) await batch.commit();
  }

  void reportStreamError(String module, Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: '$module cloud sync',
        context: ErrorDescription('while receiving Firestore updates'),
      ),
    );
  }
}
