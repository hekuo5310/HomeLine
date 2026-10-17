import 'dart:async';

import '../../domain/calls/wake_hint.dart';
export '../../domain/calls/wake_hint.dart';

import 'package:firebase_core/firebase_core.dart';

import '../../platform/call_integration/call_host.dart';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../data/local_database/local_store.dart';

/// Reserved FlutterFire path for future platform adapters. Android uses the
/// native HomeMessagingService and a single application-owned FlutterEngine.
@pragma('vm:entry-point')
Future<void> backgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
  final hint = WakeHint.parse(message.data, DateTime.now());
  if (hint == null) return;
  final store = LocalStore();
  try {
    await store.wakeHint(hint.callId, hint.expiresAt);
  } finally {
    await store.close();
  }
}

class PushService {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<String> start({
    required Future<void> Function(String?) onToken,
    required Future<void> Function(WakeHint) onHint,
  }) async {
    if (!const bool.fromEnvironment('ENABLE_FCM')) return '未启用 FCM';
    if (CallHost().supported) {
      final token = await CallHost().pushToken();
      await onToken(token);
      return token == null ? '推送令牌不可用' : 'FCM 已绑定';
    }
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(backgroundMessage);
    final messaging = FirebaseMessaging.instance;
    final permission = await messaging.requestPermission();
    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      await onToken(null);
      return '通知权限被拒绝';
    }
    // Contract v1 uses FCM registration tokens, not Firebase Installation IDs.
    // FCM 17 keeps the token API; its new onRegistered stream emits FIDs.
    // Migrate server addressing and DTO together before switching API families.
    // ignore: deprecated_member_use
    final token = await messaging.getToken();
    if (token == null) return 'FCM 尚未获取令牌';
    await onToken(token);
    _subscriptions.add(
      // ignore: deprecated_member_use
      messaging.onTokenRefresh.listen((value) {
        unawaited(onToken(value).catchError((Object _) {}));
      }),
    );
    void receive(RemoteMessage message) {
      final hint = WakeHint.parse(message.data, DateTime.now());
      if (hint != null) unawaited(onHint(hint).catchError((Object _) {}));
    }

    _subscriptions.add(FirebaseMessaging.onMessage.listen(receive));
    _subscriptions.add(FirebaseMessaging.onMessageOpenedApp.listen(receive));
    final initial = await messaging.getInitialMessage();
    if (initial != null) receive(initial);
    return 'FCM 已绑定';
  }

  Future<void> stop() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }
}
