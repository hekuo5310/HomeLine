import 'dart:async';

import '../data/dto/models.dart';
import '../domain/calls/wake_hint.dart';

abstract interface class WakeRecoveryPort {
  String get deviceId;
  Future<CallDto> lookup(String callId);
  Future<void> report(String callId, String stage);
  Future<void> ensureRegistered(Duration timeout);
  Future<void> finished(String callId);
}

/// No push message can create a SIP dialog, answer a call, or make it active.
class WakeRecovery {
  WakeRecovery(this.port, {DateTime Function()? clock})
    : now = clock ?? DateTime.now;
  final WakeRecoveryPort port;
  final DateTime Function() now;
  final _running = <String, Future<void>>{};
  final _completed = <String, DateTime>{};
  int _generation = 0;
  bool live(CallDto call) =>
      !call.terminal &&
      (call.answeredDeviceId == null ||
          call.answeredDeviceId == port.deviceId) &&
      const ['waiting', 'ringing', 'claimed'].contains(call.state);
  Future<void> receive(WakeHint hint) {
    _completed.removeWhere((_, expiry) => !expiry.isAfter(now()));
    if (!hint.expiresAt.isAfter(now()) || _completed.containsKey(hint.callId)) {
      return port.finished(hint.callId);
    }
    final generation = _generation;
    return _running.putIfAbsent(
      hint.callId,
      () => _recover(hint, generation).whenComplete(() {
        if (generation == _generation) _running.remove(hint.callId);
      }),
    );
  }

  Future<void> _recover(WakeHint hint, int generation) async {
    bool current() =>
        generation == _generation && hint.expiresAt.isAfter(now());
    try {
      await port.report(hint.callId, 'received');
      if (!current()) return;
      if (!live(await port.lookup(hint.callId))) return;
      await port.report(hint.callId, 'restored');
      if (!current()) return;
      final remaining = hint.expiresAt.difference(now());
      await port.ensureRegistered(
        remaining < const Duration(seconds: 15)
            ? remaining
            : const Duration(seconds: 15),
      );
      if (!current() || !live(await port.lookup(hint.callId))) return;
      await port.report(hint.callId, 'registered');
      // PBX delivers the real INVITE after this acknowledgement. Wait for a
      // matching SIP event, while continuing to reconcile cancellation/winner.
      while (current()) {
        final call = await port.lookup(hint.callId);
        if (!live(call)) return;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    } catch (_) {
      if (generation == _generation) {
        try {
          await port.report(hint.callId, 'failed');
        } catch (_) {}
      }
    } finally {
      if (generation == _generation) {
        _completed[hint.callId] = hint.expiresAt;
        await port.finished(hint.callId);
      }
    }
  }

  void observed(String callId) {
    // Lookup will see the server's connected/terminal state; completeWake can
    // also run immediately once Telecom owns the real incoming SIP dialog.
    unawaited(port.finished(callId).catchError((Object _) {}));
  }

  void reset() {
    _generation++;
    _running.clear();
    _completed.clear();
  }
}
