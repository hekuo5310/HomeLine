import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../core/networking/api_failure.dart';
import '../data/api/homeline_api.dart';
import '../data/dto/models.dart';
import '../data/local_database/local_store.dart';
import '../domain/calls/sip_service.dart';
import '../domain/queues/outbound_request.dart';
import '../infrastructure/push/push_service.dart';
import '../infrastructure/server_events.dart';
import '../platform/call_integration/call_integration.dart';
import 'call_controller.dart';

class AppController extends ChangeNotifier implements CallAuthority {
  AppController({
    required this.api,
    required this.sip,
    required this.platform,
    required this.vault,
    required this.store,
    ServerEvents? serverEvents,
  }) : events = serverEvents ?? ServerEvents() {
    calls = CallController(sip, platform, this);
    _subscriptions.add(
      sip.registrationStates.listen((state) {
        registration = state;
        if (state == SipRegistrationState.failed) {
          error = 'SIP 注册失败，请检查设备凭据、TLS 证书和电话服务器配置';
        }
        if (state == SipRegistrationState.stopped &&
            calls.current != null &&
            !calls.current!.terminal) {
          unawaited(
            calls.terminate(calls.current!.id).catchError((Object _) {}),
          );
        }
        _notify();
      }),
    );
    _subscriptions.add(
      sip.callEvents.listen((event) {
        unawaited(_handleSip(event));
      }),
    );
    _subscriptions.add(
      platform.actions.listen((event) {
        unawaited(
          run(() async {
            final id = event['id'] as String;
            switch (event['action']) {
              case 'answer':
                await answer(id);
              case 'reject':
                await endCall(id, true);
              case 'disconnect':
                await endCall(id, false);
              case 'audio':
                audioRoute = event['route']?.toString() ?? 'unknown';
            }
          }, independent: true),
        );
      }),
    );
  }
  final HomeLineApi api;
  final SipService sip;
  final CallIntegration platform;
  final SessionVault vault;
  final LocalStore store;
  final PushService push = PushService();
  final ServerEvents events;
  late final CallController calls;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _poll, _lease, _sessionExpiry;
  SessionDto? session;
  SnapshotDto? snapshot;
  OutboundRequest? pendingOutbound;
  SipRegistrationState registration = SipRegistrationState.stopped;
  String? error;
  String pushStatus = '未配置';
  String audioRoute = 'unknown';
  bool loading = false, restoring = true, _refreshing = false, _closed = false;
  bool _sipEnabled = false, _outboundBusy = false;
  DateTime? _credentialsExpireAt;
  bool muted = false;
  int _epoch = 0;
  bool get canCall =>
      session != null && snapshot?.canCall == true && _sipEnabled;
  @override
  String get deviceId => session?.deviceId ?? '';
  String get owner => '${session!.userId}:${session!.deviceId}';
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> run(
    Future<void> Function() operation, {
    bool independent = false,
  }) async {
    if (loading && !independent) return;
    if (!independent) loading = true;
    error = null;
    _notify();
    try {
      await operation();
    } catch (e) {
      error = e is ApiFailure
          ? e.message
          : e is StateError
          ? e.message.toString()
          : e is FormatException
          ? e.message
          : '操作失败，请检查权限、网络和服务器配置';
      if (e is ApiFailure && e.invalidSession) await _clearSession();
    } finally {
      if (!independent) loading = false;
      _notify();
    }
  }

  Future<void> restore() async {
    try {
      final saved = await vault.read();
      if (saved == null) return;
      if (!saved.expiresAt.isAfter(DateTime.now())) {
        await vault.clear();
        return;
      }
      api.token = saved.accessToken;
      // Never restore registration from an unverified local UUID or cached status.
      await _accept(await api.session());
    } catch (_) {
      await _clearSession();
      error = '会话恢复失败，请重新登录';
    } finally {
      restoring = false;
      _notify();
    }
  }

  Future<void> login(String username, String password, String name) async {
    if (username.trim().isEmpty || password.isEmpty || name.trim().isEmpty) {
      throw const FormatException('请填写用户名、密码和设备名称');
    }
    final value = await api.login(username.trim(), password, name.trim());
    api.token = value.accessToken;
    await _accept(value);
  }

  Future<void> _accept(SessionDto value) async {
    if (value.accountStatus != 'active' ||
        !value.expiresAt.isAfter(DateTime.now())) {
      api.token = null;
      throw const ApiFailure('账号不可用或会话已过期', statusCode: 403);
    }
    session = value;
    api.token = value.accessToken;
    await vault.save(value);
    pendingOutbound = await store.pending(owner);
    _sessionExpiry?.cancel();
    _sessionExpiry = Timer(value.expiresAt.difference(DateTime.now()), () {
      unawaited(_expire());
    });
    await refresh();
    if (session == null) throw const ApiFailure('会话验证失败', statusCode: 403);
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(refresh());
    });
    unawaited(
      events.start(api.dio.options.baseUrl, value.accessToken, () {
        unawaited(refresh());
      }),
    );
    try {
      pushStatus = await push.start(
        onToken: api.updatePushToken,
        onHint: (_) async {
          await refresh(); // A push cannot create/answer/activate a call.
        },
      );
    } catch (_) {
      pushStatus = '推送配置或令牌绑定失败，可重新登录重试';
    }
    _notify();
  }

  Future<void> _expire() async {
    await _clearSession();
    error = '登录已过期，请重新登录';
    _notify();
  }

  Future<void> refresh() async {
    if (_refreshing || session == null) return;
    _refreshing = true;
    final epoch = _epoch;
    try {
      final value = await api.snapshot();
      if (epoch != _epoch || session == null) return;
      if (value.accountStatus != 'active' || value.deviceStatus != 'active') {
        throw const ApiFailure('账号已禁用或设备已撤销', statusCode: 403);
      }
      snapshot = value;
      _lease?.cancel();
      _lease = Timer(const Duration(seconds: 30), () {
        unawaited(_stopForLostLease());
      });
      if ((!_sipEnabled ||
              (_credentialsExpireAt?.isBefore(
                    DateTime.now().add(const Duration(seconds: 30)),
                  ) ??
                  true)) &&
          value.canCall &&
          (calls.current == null || calls.current!.terminal)) {
        final credentials = await api.sipCredentials();
        if (epoch != _epoch || session == null) return;
        await sip.register(
          SipConfiguration(
            webSocketUrl: credentials.webSocketUrl,
            uri: credentials.uri,
            authorizationUser: credentials.authorizationUser,
            password: credentials.password,
            expiresAt: credentials.expiresAt,
            iceServers: credentials.iceServers,
          ),
        );
        _credentialsExpireAt = credentials.expiresAt;
        _sipEnabled = true;
      }
      if (!value.canCall && _sipEnabled) {
        await _stopSip();
        _sipEnabled = false;
      }
      for (final call in value.calls) {
        await calls.applyServerCall(call);
      }
    } catch (e) {
      if (epoch != _epoch) return;
      if (e is ApiFailure && e.invalidSession) {
        await _clearSession();
        error = e.message;
      } else {
        error = '状态同步失败；30 秒无法验证权限时会停止 SIP';
      }
    } finally {
      _refreshing = false;
      _notify();
    }
  }

  Future<void> _stopSip() async {
    _sipEnabled = false;
    final current = calls.current;
    try {
      if (current != null && !current.terminal) {
        await calls.terminate(current.id);
      }
    } finally {
      await sip.unregister();
    }
  }

  Future<void> _stopForLostLease() async {
    await _stopSip();
    error = '无法验证设备权限，SIP 已停止；网络恢复后自动重试';
    _notify();
  }

  Future<void> _handleSip(SipCallEvent event) async {
    try {
      await calls.onSipEvent(event);
      if (event.phase == CallPhase.failed) error = event.reason;
      if (event.terminal) await refresh();
    } catch (_) {
      error = 'Android 电话集成失败，请启用 HomeLine 通话账号';
    }
    _notify();
  }

  Future<void> configureTelecom() async {
    await _permission();
    await Permission.notification.request();
    await platform.configure();
  }

  Future<void> _permission() async {
    if (!await Permission.microphone.request().isGranted) {
      throw StateError('需要麦克风权限');
    }
  }

  Future<void> dial(String extension) async {
    await refresh();
    if (!canCall) throw StateError('没有呼叫权限或服务未就绪');
    await _permission();
    await sip.dial(extension);
  }

  Future<void> answer(String id) async {
    await refresh();
    if (!canCall) throw StateError('账号或设备当前不可接听');
    await _permission();
    await calls.answer(
      id,
      const Uuid().v5(
        '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
        '$deviceId:$id:answer',
      ),
    );
  }

  Future<void> endCall(String id, bool reject) => calls.endByUser(
    id,
    reject,
    const Uuid().v5(
      '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
      '$deviceId:$id:${reject ? 'reject' : 'hangup'}',
    ),
  );
  Future<void> setMuted(bool value) async {
    if (calls.current == null) return;
    await sip.mute(calls.current!.id, value);
    muted = value;
  }

  Future<void> route(String route) async {
    if (route == 'bluetooth' &&
        !await Permission.bluetoothConnect.request().isGranted) {
      throw StateError('需要蓝牙连接权限');
    }
    await platform.route(calls.current!.id, route);
  }

  Future<void> outbound(String destination) async {
    if (_outboundBusy) return;
    _outboundBusy = true;
    try {
      await refresh();
      if (!canCall) throw StateError('当前不可外呼');
      pendingOutbound ??= OutboundRequest(destination);
      if (pendingOutbound!.destination != destination) {
        throw StateError('有未确认的外呼请求，请先重试原请求以确认结果');
      }
      // Persist before sending: process death/retries cannot change the key.
      await store.saveIntent(owner, pendingOutbound!);
      await api.submitOutbound(destination, pendingOutbound!.idempotencyKey);
      await store.resolveIntent(owner);
      pendingOutbound = null;
      await refresh();
    } finally {
      _outboundBusy = false;
    }
  }

  Future<void> cancelTask(QueueTaskDto task) async {
    if (task.state != 'waiting') throw StateError('只有等待中的任务可以取消');
    await api.cancelTask(task.id, 'cancel:${task.id}');
    await refresh();
  }

  Future<void> renameDevice(DeviceDto device, String name) async {
    if (name.trim().isEmpty || name.length > 80) {
      throw const FormatException('设备名需为 1–80 字符');
    }
    await api.renameDevice(device.id, name.trim());
    await refresh();
  }

  Future<void> revoke(DeviceDto device) async {
    await api.revokeDevice(device.id, 'revoke:${device.id}');
    if (device.id == deviceId) {
      await _clearSession();
    } else {
      await refresh();
    }
  }

  Future<void> logout() async {
    Object? failure;
    try {
      await api.updatePushToken(null);
      await api.logout();
    } catch (e) {
      failure = e;
    } finally {
      await _clearSession();
    }
    if (failure != null) throw const ApiFailure('本机已退出；服务器会话撤销未确认，请在其他设备撤销本机');
  }

  Future<void> _clearSession() async {
    _epoch++;
    _poll?.cancel();
    _lease?.cancel();
    _sessionExpiry?.cancel();
    events.stop();
    await push.stop();
    try {
      await _stopSip();
    } catch (_) {
      // Session revocation must still clear secrets when platform cleanup fails.
    }
    calls.reset();
    api.token = null;
    session = null;
    snapshot = null;
    pendingOutbound = null;
    await vault.clear();
    await store.clear();
    _notify();
  }

  @override
  Future<CallDto> resolve(String sipId) => api.callForSip(sipId);
  @override
  Future<CallDto> claim(String callId, String key) =>
      api.callAction(callId, 'claim', key);
  @override
  Future<CallDto> action(String callId, String action, String key) =>
      api.callAction(callId, action, key);
  @override
  void dispose() {
    _closed = true;
    _poll?.cancel();
    _lease?.cancel();
    _sessionExpiry?.cancel();
    events.stop();
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    unawaited(push.stop());
    unawaited(sip.dispose());
    unawaited(store.close());
    api.close();
    super.dispose();
  }
}
