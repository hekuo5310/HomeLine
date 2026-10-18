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
import 'wake_recovery.dart';
import '../platform/call_integration/call_host.dart';

class AppController extends ChangeNotifier
    implements CallAuthority, WakeRecoveryPort {
  AppController({
    required this.api,
    required this.sip,
    required this.platform,
    required this.vault,
    required this.store,
    ServerEvents? serverEvents,
    CallHost? callHost,
  }) : events = serverEvents ?? ServerEvents(),
       host = callHost ?? CallHost() {
    calls = CallController(sip, platform, this);
    recovery = WakeRecovery(this);
    _subscriptions.add(
      host.events.listen((event) {
        unawaited(
          run(() async {
            switch (event['event']) {
              case 'wake':
                final hint = WakeHint.parse(event, DateTime.now());
                if (hint != null) await recovery.receive(hint);
              case 'interrupted':
                await _reconcileInterrupted(event['call_id'] as String);
              case 'tokenChanged':
                if (session != null) await _syncNativePush();
              case 'invalidate':
                await refresh();
            }
          }, independent: true),
        );
      }),
    );
    _subscriptions.add(
      sip.registrationStates.listen((state) {
        registration = state;
        if (state == SipRegistrationState.expired) _sipEnabled = false;
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
        // CANCEL/BYE must clear native ringing even while an HTTP resolve waits.
        if (event.terminal) {
          unawaited(_handleSip(event));
          return;
        }
        final epoch = _epoch;
        _sipWork = _sipWork.then((_) async {
          if (!_closed && epoch == _epoch) await _handleSip(event);
        });
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
              case 'focusLost':
                try {
                  await calls.terminate(id);
                } finally {
                  await host.releaseFocus();
                }
              case 'audio':
                audioRoute = event['route']?.toString() ?? 'unknown';
            }
          }, independent: true),
        );
      }),
    );
  }
  final CallHost host;
  late final WakeRecovery recovery;
  final HomeLineApi api;
  final SipService sip;
  final CallIntegration platform;
  final SessionVault vault;
  final LocalStore store;
  final PushService push = PushService();
  final ServerEvents events;
  late final CallController calls;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _poll, _lease, _sessionExpiry, _pushRetry, _restoreRetry;
  Future<void> _sipWork = Future<void>.value();
  Future<void>? _clearing;
  SessionDto? session;
  SnapshotDto? snapshot;
  OutboundRequest? pendingOutbound;
  SipRegistrationState registration = SipRegistrationState.stopped;
  String? error;
  String pushStatus = '未配置';
  String? diagnostics;
  bool hideCaller = true;
  final pushStages = <String, DateTime>{};
  final _interrupting = <String>{};
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
    await _clearing;
    final epoch = _epoch;
    try {
      final saved = await vault.read();
      if (epoch != _epoch || saved == null) return;
      if (!saved.expiresAt.isAfter(DateTime.now())) {
        await vault.clear();
        return;
      }
      api.token = saved.accessToken;
      final verified = await api.session();
      if (epoch != _epoch) return;
      await _accept(verified);
    } catch (e) {
      if (epoch != _epoch) return;
      if (e is ApiFailure && e.invalidSession) {
        await _clearSession();
        error = '会话无效，请重新登录';
      } else {
        // An offline launch must not erase a valid device session.
        error = '暂时无法验证会话，网络恢复后重试';
        _restoreRetry?.cancel();
        _restoreRetry = Timer(const Duration(seconds: 5), () {
          if (!_closed && session == null) unawaited(restore());
        });
      }
    } finally {
      restoring = false;
      _notify();
    }
  }

  Future<void> login(String username, String password, String name) async {
    await _clearing;
    if (username.trim().isEmpty || password.isEmpty || name.trim().isEmpty) {
      throw const FormatException('请填写用户名、密码和设备名称');
    }
    _restoreRetry?.cancel();
    final epoch = ++_epoch;
    final value = await api.login(username.trim(), password, name.trim());
    if (epoch != _epoch) throw StateError('会话已变化，请重新登录');
    api.token = value.accessToken;
    await _accept(value);
  }

  Future<void> _accept(SessionDto value) async {
    if (value.accountStatus != 'active' ||
        !value.expiresAt.isAfter(DateTime.now())) {
      api.token = null;
      throw const ApiFailure('账号不可用或会话已过期', statusCode: 403);
    }
    final epoch = ++_epoch;
    _restoreRetry?.cancel();
    session = value;
    snapshot = null;
    api.token = value.accessToken;
    await vault.save(value);
    if (epoch != _epoch || session != value) {
      throw StateError('会话已变化，请重新操作');
    }
    pendingOutbound = await store.pending('${value.userId}:${value.deviceId}');
    if (epoch != _epoch || session != value) {
      throw StateError('会话已变化，请重新操作');
    }
    _sessionExpiry?.cancel();
    _sessionExpiry = Timer(value.expiresAt.difference(DateTime.now()), () {
      unawaited(_expire());
    });
    await refresh();
    if (epoch != _epoch || session != value) {
      throw StateError('会话已变化，请重新操作');
    }
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(refresh());
    });
    unawaited(
      events.start(api.dio.options.baseUrl, value.accessToken, () {
        unawaited(refresh());
      }),
    );
    unawaited(_startPush(epoch));
    try {
      await host.ready();
    } catch (_) {
      error = '原生通话服务初始化失败，请重新打开应用';
    }
    _notify();
  }

  Future<void> _startPush(int epoch) async {
    try {
      final result = await push.start(
        onToken: (token) async {
          if (epoch == _epoch && session != null) {
            await api.updatePushToken(token);
          }
        },
        onHint: recovery.receive,
      );
      if (epoch == _epoch) pushStatus = result;
    } catch (_) {
      if (epoch == _epoch) {
        pushStatus = '推送令牌绑定失败，正在重试';
        if (host.supported) {
          _pushRetry = Timer(const Duration(seconds: 5), () {
            unawaited(_syncNativePush());
          });
        }
      }
    }
    _notify();
  }

  Future<void> _syncNativePush() async {
    if (!const bool.fromEnvironment('ENABLE_FCM') || session == null) return;
    final epoch = _epoch;
    try {
      final token = await host.pushToken();
      if (epoch != _epoch || session == null) return;
      await api.updatePushToken(token);
      pushStatus = token == null ? '推送令牌不可用' : 'FCM 已绑定';
    } catch (e) {
      if (epoch != _epoch) return;
      if (e is ApiFailure && e.invalidSession) {
        await _clearSession();
      } else {
        pushStatus = '推送同步失败，稍后重试';
        _pushRetry?.cancel();
        _pushRetry = Timer(const Duration(seconds: 15), () {
          unawaited(_syncNativePush());
        });
      }
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
    final epoch = _epoch;
    _sipEnabled = false;
    final current = calls.current;
    try {
      if (current != null && !current.terminal) {
        await calls.terminate(current.id);
      }
    } finally {
      if (epoch == _epoch) await sip.unregister();
    }
  }

  Future<void> _stopForLostLease() async {
    await _stopSip();
    error = '无法验证设备权限，SIP 已停止；网络恢复后自动重试';
    _notify();
  }

  Future<void> _handleSip(SipCallEvent event) async {
    final epoch = _epoch;
    if (session == null) return;
    try {
      // Reconcile a real INVITE with server ownership before showing Telecom.
      // Unknown or stale device legs are rejected instead of ringing optimistically.
      CallDto? authority;
      if (event.incoming && !event.terminal) {
        authority = await api.callForSip(event.id);
        if (epoch != _epoch) return;
        await calls.applyServerCall(authority);
      }
      if (epoch != _epoch) return;
      await calls.onSipEvent(event);
      if (authority != null &&
          calls.current?.id == event.id &&
          calls.current?.terminal == false) {
        recovery.observed(authority.id);
        unawaited(
          report(
            authority.id,
            event.phase == CallPhase.active ? 'connected' : 'ringing',
          ).catchError((Object _) {
            if (epoch == _epoch) {
              error = '通话状态回执未确认，正在同步';
              _notify();
            }
          }),
        );
      }
      if (event.phase == CallPhase.failed) error = event.reason;
      if (event.phase == CallPhase.active && calls.current?.terminal == false) {
        try {
          final call = authority ?? await api.callForSip(event.id);
          await host.journal(call.id, true);
        } catch (_) {
          error = '通话恢复记录暂时不可用';
        }
      }
      if (event.terminal) {
        try {
          final call = await api.callForSip(event.id);
          await host.journal(call.id, false);
        } catch (_) {}
        await refresh();
      }
    } catch (_) {
      if (event.incoming && !event.terminal) {
        try {
          await calls.terminate(event.id);
        } catch (_) {}
      }
      error = '呼叫验证或系统通话集成失败，请检查服务器和通话权限';
    }
    _notify();
  }

  Future<void> _reconcileInterrupted(String id) async {
    if (session == null || !_interrupting.add(id)) return;
    try {
      try {
        final call = await api.callById(id);
        if (!call.terminal && call.answeredDeviceId == deviceId) {
          await report(id, 'media_lost');
        }
      } on ApiFailure catch (e) {
        if (e.statusCode != 404) rethrow;
      }
      await host.journal(id, false);
    } finally {
      _interrupting.remove(id);
    }
  }

  Future<void> diagnose() async {
    final watch = Stopwatch()..start();
    final status = await api.snapshot();
    final native = await host.status();
    hideCaller = await host.privacy();
    diagnostics =
        'HTTPS API：${watch.elapsedMilliseconds} ms\n账号：${status.accountStatus}；设备：${status.deviceStatus}\nSIP：${registration.name}；音频：$audioRoute\n通知：${native['notifications'] ?? '此平台未提供'}；全屏来电：${native['full_screen'] ?? '此平台未提供'}\n麦克风：${await Permission.microphone.status}\n推送：$pushStatus\n${pushStages.entries.map((e) => '${e.key}: ${e.value.toLocal()}').join('\n')}';
  }

  Future<void> setHideCaller(bool value) async {
    hideCaller = await host.privacy(value);
  }

  Future<void> configureTelecom() async {
    await _permission();
    await Permission.notification.request();
    await platform.configure();
  }

  Future<void> _permission() async {
    if (await Permission.microphone.isGranted) return;
    if (host.supported && (await host.status())['visible'] != true) {
      throw StateError('请打开应用授予麦克风权限');
    }
    if (!await Permission.microphone.request().isGranted) {
      throw StateError('需要麦克风权限');
    }
  }

  Future<void> dial(String extension) async {
    await refresh();
    if (!canCall) throw StateError('没有呼叫权限或服务未就绪');
    await _permission();
    await host.keepAlive();
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
      try {
        await api.updatePushToken(null);
      } catch (_) {}
      await api.logout();
    } catch (e) {
      failure = e;
    } finally {
      await _clearSession();
    }
    if (failure != null) throw const ApiFailure('本机已退出；服务器会话撤销未确认，请在其他设备撤销本机');
  }

  Future<void> _clearSession() =>
      _clearing ??= _doClearSession().whenComplete(() {
        _clearing = null;
      });

  Future<void> _doClearSession() async {
    _epoch++;
    recovery.reset();
    _restoreRetry?.cancel();
    _poll?.cancel();
    _lease?.cancel();
    _sessionExpiry?.cancel();
    _pushRetry?.cancel();
    events.stop();
    // Invalidate immediately, before any platform/network cleanup can suspend.
    api.token = null;
    session = null;
    snapshot = null;
    pendingOutbound = null;
    _sipEnabled = false;
    try {
      await host.clear();
    } catch (_) {}
    try {
      await push.stop();
    } catch (_) {}
    try {
      await _stopSip();
    } catch (_) {
      // Session revocation must still clear secrets when platform cleanup fails.
    }
    calls.reset();
    await vault.clear();
    await store.clear();
    _notify();
  }

  @override
  Future<CallDto> lookup(String callId) => api.callById(callId);
  @override
  Future<void> report(String callId, String stage) async {
    await api.deviceEvent(
      callId,
      stage,
      const Uuid().v5(
        '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
        '$deviceId:$callId:$stage',
      ),
    );
    pushStages[stage] = DateTime.now();
  }

  @override
  Future<void> finished(String callId) => host.completeWake(callId);
  @override
  Future<void> ensureRegistered(Duration timeout) async {
    if (session == null) throw StateError('会话未恢复');
    await refresh();
    if (!_sipEnabled || snapshot?.deviceStatus != 'active') {
      throw StateError('设备当前不可注册');
    }
    if (registration == SipRegistrationState.registered) return;
    await sip.registrationStates
        .firstWhere((s) => s == SipRegistrationState.registered)
        .timeout(timeout);
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
    _restoreRetry?.cancel();
    _poll?.cancel();
    _lease?.cancel();
    _sessionExpiry?.cancel();
    _pushRetry?.cancel();
    events.stop();
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    recovery.reset();
    unawaited(host.dispose());
    unawaited(push.stop());
    final call = calls.current;
    if (call != null && !call.terminal) unawaited(platform.end(call.id));
    unawaited(sip.dispose());
    unawaited(store.close());
    api.close();
    super.dispose();
  }
}
