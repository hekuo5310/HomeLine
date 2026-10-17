import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Engine-owned host; contains no SIP or FCM-specific domain state.
class CallHost {
  static const channel = MethodChannel('net.zerexa.homeline/host');
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Stream<Map<String, dynamic>> get events => _events.stream;
  Future<void> ready() async {
    if (!supported) return;
    channel.setMethodCallHandler((call) async {
      _events.add({
        'event': call.method,
        if (call.arguments is Map)
          ...Map<String, dynamic>.from(call.arguments as Map),
      });
    });
    await channel.invokeMethod<void>('ready');
  }

  Future<void> completeWake(String id) async {
    if (supported) {
      await channel.invokeMethod<void>('completeWake', {'call_id': id});
    }
  }

  Future<bool> privacy([bool? hidden]) async => supported
      ? await channel.invokeMethod<bool>('privacy', {'hide_caller': ?hidden}) ??
            true
      : true;
  Future<void> journal(String id, bool active) async {
    if (supported) {
      await channel.invokeMethod<void>(
        active ? 'journalActive' : 'journalEnd',
        {'call_id': id},
      );
    }
  }

  Future<void> clear() async {
    if (supported) await channel.invokeMethod<void>('clear');
  }

  Future<void> releaseFocus() async {
    if (supported) await channel.invokeMethod<void>('releaseFocus');
  }

  Future<void> keepAlive() async {
    if (supported) await channel.invokeMethod<void>('keepAlive');
  }

  Future<String?> pushToken() => channel
      .invokeMethod<String>('token')
      .timeout(const Duration(seconds: 10));
  Future<Map<String, dynamic>> status() async => supported
      ? Map<String, dynamic>.from(
          await channel.invokeMethod<Map>('status') ?? {},
        )
      : {};
  Future<void> dispose() async {
    if (supported) channel.setMethodCallHandler(null);
    await _events.close();
  }
}
