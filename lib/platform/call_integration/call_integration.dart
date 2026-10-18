import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class CallIntegration {
  Stream<Map<String, dynamic>> get actions;
  Future<void> configure();
  Future<void> show(String id, String remote, bool incoming);
  Future<void> active(String id);
  Future<void> end(String id);
  Future<void> route(String id, String route);
}

class AndroidCallIntegration implements CallIntegration {
  AndroidCallIntegration() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action') {
        _actions.add(Map<String, dynamic>.from(call.arguments as Map));
      }
    });
  }
  static const _channel = MethodChannel('net.zerexa.homeline/telecom');
  final _actions = StreamController<Map<String, dynamic>>.broadcast();
  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  @override
  Stream<Map<String, dynamic>> get actions => _actions.stream;
  @override
  Future<void> configure() async {
    if (_supported) await _channel.invokeMethod<void>('configure');
  }

  @override
  Future<void> show(String id, String remote, bool incoming) async {
    if (_supported) {
      await _channel.invokeMethod<void>('show', {
        'id': id,
        'remote': remote,
        'incoming': incoming,
      });
    }
  }

  @override
  Future<void> active(String id) async {
    if (_supported) await _channel.invokeMethod<void>('active', {'id': id});
  }

  @override
  Future<void> end(String id) async {
    if (_supported) await _channel.invokeMethod<void>('end', {'id': id});
  }

  @override
  Future<void> route(String id, String route) async {
    if (_supported) {
      await _channel.invokeMethod<void>('route', {'id': id, 'route': route});
    } else {
      throw UnsupportedError('此平台音频路由尚未接入');
    }
  }
}
