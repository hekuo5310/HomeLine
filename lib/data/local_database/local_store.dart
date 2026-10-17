import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/queues/outbound_request.dart';
import '../dto/models.dart';

class SessionVault {
  const SessionVault();
  static const _storage = FlutterSecureStorage();
  Future<SessionDto?> read() async {
    final value = await _storage.read(key: 'session');
    if (value == null) return null;
    try {
      return SessionDto.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> save(SessionDto session) =>
      _storage.write(key: 'session', value: jsonEncode(session.toJson()));
  Future<void> clear() => _storage.delete(key: 'session');
}

/// Contains no access token, SIP password or FCM token.
class LocalStore {
  Database? _db;
  Future<Database> get db async => _db ??= await openDatabase(
    '${await getDatabasesPath()}/homeline.db',
    version: 1,
    onCreate: (db, _) async {
      await db.execute(
        'CREATE TABLE outbound_intent (owner TEXT PRIMARY KEY, destination TEXT NOT NULL, request_key TEXT NOT NULL)',
      );
      await db.execute(
        'CREATE TABLE wake_hint (call_id TEXT PRIMARY KEY, expires_at INTEGER NOT NULL)',
      );
    },
  );
  Future<void> saveIntent(String owner, OutboundRequest intent) async =>
      (await db).insert('outbound_intent', {
        'owner': owner,
        'destination': intent.destination,
        'request_key': intent.idempotencyKey,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<OutboundRequest?> pending(String owner) async {
    final rows = await (await db).query(
      'outbound_intent',
      where: 'owner = ?',
      whereArgs: [owner],
    );
    return rows.isEmpty
        ? null
        : OutboundRequest.restore(
            rows.single['destination'] as String,
            rows.single['request_key'] as String,
          );
  }

  Future<void> resolveIntent(String owner) async => (await db).delete(
    'outbound_intent',
    where: 'owner = ?',
    whereArgs: [owner],
  );
  Future<void> wakeHint(String callId, DateTime expires) async {
    final database = await db;
    await database.delete(
      'wake_hint',
      where: 'expires_at < ?',
      whereArgs: [DateTime.now().millisecondsSinceEpoch],
    );
    await database.insert('wake_hint', {
      'call_id': callId,
      'expires_at': expires.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> clear() async {
    final database = await db;
    await database.delete('outbound_intent');
    await database.delete('wake_hint');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
