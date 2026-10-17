import 'dart:async';

import '../domain/calls/sip_service.dart';
import '../core/networking/api_failure.dart';
import '../data/dto/models.dart';
import '../platform/call_integration/call_integration.dart';

abstract interface class CallAuthority {
  Future<CallDto> resolve(String sipId);
  Future<CallDto> claim(String callId, String key);
  Future<CallDto> action(String callId, String action, String key);
  String get deviceId;
}

/// Server owns the answer lease; only a confirmed SIP dialog activates Telecom.
class CallController {
  CallController(this.sip, this.platform, this.authority);
  final SipService sip;
  final CallIntegration platform;
  final CallAuthority authority;
  SipCallEvent? current;
  DateTime? connectedAt;
  String? outcome;
  int _generation = 0;
  final _busy = <String>{};
  final _ended = <String>{};
  final _shown = <String>{};
  final _revisions = <String, int>{};

  Future<void> onSipEvent(SipCallEvent event) async {
    if (_ended.contains(event.id)) {
      if (!event.terminal) await sip.hangup(event.id);
      return;
    }
    if (event.terminal) {
      _ended.add(event.id);
      current = event;
      connectedAt = null;
      await platform.end(event.id);
      return;
    }
    // Don't regress an active dialog on late ringing/progress callbacks.
    if (current?.id == event.id &&
        current?.phase == CallPhase.active &&
        event.phase != CallPhase.active) {
      return;
    }
    current = event;
    if (_shown.add(event.id)) {
      try {
        await platform.show(event.id, event.remote, event.incoming);
      } catch (_) {
        _shown.remove(event.id);
        rethrow;
      }
    }
    if (_ended.contains(event.id)) {
      await platform.end(event.id);
      return;
    }
    if (event.phase == CallPhase.active) {
      connectedAt ??= DateTime.now();
      await platform.active(event.id);
    }
  }

  Future<void> answer(String sipId, String key) async {
    if (!_busy.add(sipId)) return;
    final generation = _generation;
    try {
      if (_ended.contains(sipId) ||
          current?.id != sipId ||
          current?.phase != CallPhase.ringing) {
        throw StateError('来电已结束或不处于振铃状态');
      }
      final call = await authority.resolve(sipId);
      if (_ended.contains(sipId) || generation != _generation) return;
      final result = await authority.claim(call.id, key);
      if (_ended.contains(sipId) || generation != _generation) return;
      if (result.answeredDeviceId != authority.deviceId || result.terminal) {
        outcome = '已由其他设备接听或来电已结束';
        await terminate(sipId);
        return;
      }
      // Claim success is not a connected call. Wait for SIP CONFIRMED.
      await sip.answer(sipId);
    } on ApiFailure catch (e) {
      if (e.statusCode == 409) {
        outcome = '已由其他设备接听或来电已结束';
        await terminate(sipId);
      }
      rethrow;
    } finally {
      _busy.remove(sipId);
    }
  }

  Future<void> terminate(String sipId, {bool reject = false}) async {
    _ended.add(sipId);
    try {
      if (reject) {
        await sip.reject(sipId);
      } else {
        await sip.hangup(sipId);
      }
    } finally {
      if (current?.id == sipId) {
        current = SipCallEvent(
          id: sipId,
          phase: CallPhase.ended,
          incoming: current!.incoming,
          remote: current!.remote,
        );
        connectedAt = null;
      }
      await platform.end(sipId);
    }
  }

  Future<void> endByUser(String sipId, bool reject, String key) async {
    if (!_busy.add(sipId) || _ended.contains(sipId)) return;
    try {
      // Stop local audio even when the REST acknowledgement is unavailable.
      await terminate(sipId, reject: reject);
      final call = await authority.resolve(sipId);
      await authority.action(call.id, reject ? 'reject' : 'hangup', key);
    } finally {
      _busy.remove(sipId);
    }
  }

  Future<void> applyServerCall(CallDto call) async {
    if (call.revision <= (_revisions[call.id] ?? -1)) return;
    _revisions[call.id] = call.revision;
    if (call.terminal ||
        (call.answeredDeviceId != null &&
            call.answeredDeviceId != authority.deviceId)) {
      if (call.answeredDeviceId != null &&
          call.answeredDeviceId != authority.deviceId) {
        outcome = '已由其他设备接听';
      }
      if (current?.id == call.sipCallId && !current!.terminal) {
        await terminate(call.sipCallId);
      } else {
        _ended.add(call.sipCallId);
        await platform.end(call.sipCallId);
      }
    }
  }

  void reset() {
    _generation++;
    current = null;
    connectedAt = null;
    outcome = null;
    _ended.clear();
    _shown.clear();
    _revisions.clear();
  }
}
