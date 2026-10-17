import 'dart:async';

import 'package:logger/logger.dart';
import 'package:sip_ua/sip_ua.dart' as sdk;

import '../../domain/calls/sip_service.dart';

/// SIP over WSS/TLS and WebRTC DTLS-SRTP; never plaintext WS/TCP.
class SipUaService implements SipService, sdk.SipUaHelperListener {
  SipUaService()
    : _helper = sdk.SIPUAHelper(customLogger: Logger(level: Level.off)) {
    _helper.addSipUaHelperListener(this);
  }
  sdk.SIPUAHelper _helper;
  final _registrations = StreamController<SipRegistrationState>.broadcast();
  final _events = StreamController<SipCallEvent>.broadcast();
  final Map<String, sdk.Call> _calls = {};
  bool _enabled = false;
  Timer? _expiry;
  @override
  Stream<SipRegistrationState> get registrationStates => _registrations.stream;
  @override
  Stream<SipCallEvent> get callEvents => _events.stream;
  @override
  Future<void> register(SipConfiguration configuration) async {
    if (!configuration.expiresAt.isAfter(DateTime.now())) {
      throw StateError('SIP 凭据已过期');
    }
    await unregister();
    _helper.removeSipUaHelperListener(this);
    _helper = sdk.SIPUAHelper(customLogger: Logger(level: Level.off));
    _helper.addSipUaHelperListener(this);
    _enabled = true;
    _registrations.add(SipRegistrationState.connecting);
    final settings = sdk.UaSettings()
      ..transportType = sdk.TransportType.WS
      ..webSocketUrl = configuration.webSocketUrl
      ..uri = configuration.uri
      ..authorizationUser = configuration.authorizationUser
      ..password = configuration.password
      ..register = true
      ..userAgent = 'HomeLine/0.1'
      ..iceServers = configuration.iceServers
      ..connectionRecoveryMinInterval = 2
      ..connectionRecoveryMaxInterval = 30;
    settings.webSocketSettings.allowBadCertificate = false;
    _expiry = Timer(configuration.expiresAt.difference(DateTime.now()), () {
      unawaited(unregister());
    });
    await _helper.start(settings);
  }

  @override
  Future<void> unregister() async {
    _enabled = false;
    _expiry?.cancel();
    for (final call in _calls.values.toList()) {
      call.hangup();
    }
    _calls.clear();
    if (_helper.registered) await _helper.unregister(false);
    _helper.stop();
    _registrations.add(SipRegistrationState.stopped);
  }

  sdk.Call _call(String id) =>
      _calls[id] ?? (throw StateError('SIP 呼叫已结束或尚未恢复'));
  @override
  Future<void> dial(String destination) async {
    if (!_enabled || !_helper.registered) throw StateError('SIP 尚未注册');
    if (!RegExp(r'^[0-9]{2,8}$').hasMatch(destination)) {
      throw const FormatException('仅允许个人分机直拨；外线请提交排队任务');
    }
    if (_calls.isNotEmpty) throw StateError('已有活动通话');
    if (!await _helper.call(destination, voiceOnly: true)) {
      throw StateError('无法发起 SIP 呼叫');
    }
  }

  @override
  Future<void> answer(String callId) async {
    if (!_enabled) throw StateError('SIP 已停止');
    _call(callId).answer(_helper.buildCallOptions(true));
  }

  @override
  Future<void> reject(String callId) async =>
      _calls[callId]?.hangup({'status_code': 486});
  @override
  Future<void> hangup(String callId) async => _calls[callId]?.hangup();
  @override
  Future<void> mute(String callId, bool muted) async {
    final call = _call(callId);
    if (muted) {
      call.mute(true, false);
    } else {
      call.unmute(true, false);
    }
  }

  @override
  void callStateChanged(sdk.Call call, sdk.CallState state) {
    // sip_ua's helper ID includes a dialog tag. The backend resolves the
    // wire Call-ID of this device's leg, never the helper's composite ID.
    final String? id = call.session.request?.call_id as String?;
    if (id == null) return;
    if (!_enabled) {
      call.hangup();
      return;
    }
    final incoming = call.direction == sdk.Direction.incoming;
    final phase = switch (state.state) {
      sdk.CallStateEnum.CALL_INITIATION =>
        incoming ? CallPhase.ringing : CallPhase.dialing,
      sdk.CallStateEnum.CONNECTING => CallPhase.connecting,
      sdk.CallStateEnum.PROGRESS =>
        incoming ? CallPhase.ringing : CallPhase.dialing,
      sdk.CallStateEnum.CONFIRMED => CallPhase.active,
      sdk.CallStateEnum.ENDED => CallPhase.ended,
      sdk.CallStateEnum.FAILED => CallPhase.failed,
      _ => null,
    };
    if (phase == null) return;
    // One audio call at a time; no client-side queue ownership.
    if (_calls.isNotEmpty && !_calls.containsKey(id)) {
      call.hangup({'status_code': 486});
      return;
    }
    final terminal = phase == CallPhase.ended || phase == CallPhase.failed;
    if (terminal) {
      _calls.remove(id);
    } else {
      _calls[id] = call;
    }
    _events.add(
      SipCallEvent(
        id: id,
        phase: phase,
        incoming: incoming,
        remote: call.remote_identity ?? '未知号码',
        reason: phase == CallPhase.failed
            ? _failureMessage(state.cause?.status_code)
            : null,
      ),
    );
  }

  String _failureMessage(int? code) => switch (code) {
    401 || 407 => 'SIP 认证失败，请重新登录获取设备凭据',
    403 || 603 => '对端拒绝通话或无呼叫权限',
    404 => '目标分机不存在',
    408 || 480 => '呼叫超时或对端暂时离线',
    486 || 600 => '对端忙线',
    487 => '呼叫已取消',
    488 => '安全媒体协商失败，请检查 DTLS-SRTP 配置',
    503 => '电话服务器暂时不可用',
    _ => 'SIP 呼叫失败，请检查网络和设备权限',
  };

  @override
  void registrationStateChanged(sdk.RegistrationState state) {
    if (!_enabled) return;
    _registrations.add(switch (state.state) {
      sdk.RegistrationStateEnum.REGISTERED => SipRegistrationState.registered,
      sdk.RegistrationStateEnum.REGISTRATION_FAILED =>
        SipRegistrationState.failed,
      _ => SipRegistrationState.connecting,
    });
  }

  @override
  void transportStateChanged(sdk.TransportState state) {
    if (_enabled && state.state == sdk.TransportStateEnum.DISCONNECTED) {
      _registrations.add(SipRegistrationState.connecting);
    }
  }

  @override
  void onNewMessage(sdk.SIPMessageRequest msg) {}
  @override
  void onNewNotify(sdk.Notify ntf) {}
  @override
  void onNewReinvite(sdk.ReInvite event) {
    event.reject?.call({'status_code': 488});
  }

  @override
  Future<void> dispose() async {
    await unregister();
    _helper.removeSipUaHelperListener(this);
    await _registrations.close();
    await _events.close();
  }
}
