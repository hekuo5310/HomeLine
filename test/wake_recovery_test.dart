import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeline/application/wake_recovery.dart';
import 'package:homeline/data/dto/models.dart';
import 'package:homeline/infrastructure/push/push_service.dart';

class Port implements WakeRecoveryPort {
  @override
  String get deviceId => 'device';
  final stages = <String>[];
  int registrations = 0, finishes = 0, lookups = 0;
  Completer<void>? registrationGate;
  String state = 'ringing';
  String? winner;
  @override
  Future<CallDto> lookup(String callId) async {
    lookups++;
    return CallDto(
      id: callId,
      sipCallId: 'wire',
      state: state,
      remote: '1001',
      updatedAt: DateTime.now(),
      revision: 1,
      answeredDeviceId: winner,
    );
  }

  @override
  Future<void> report(String callId, String stage) async {
    stages.add(stage);
  }

  @override
  Future<void> ensureRegistered(Duration timeout) async {
    registrations++;
    if (registrationGate != null) await registrationGate!.future;
  }

  @override
  Future<void> finished(String callId) async {
    finishes++;
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 18);
  WakeHint hint() => WakeHint('business', now.add(const Duration(seconds: 30)));
  test('Expired hints never authenticate or register', () async {
    final port = Port();
    final recovery = WakeRecovery(port, clock: () => now);
    await recovery.receive(WakeHint('old', now));
    expect(port.stages, isEmpty);
    expect(port.registrations, 0);
    expect(port.finishes, 1);
  });
  test('Cancelled and other-device answered calls never restore SIP', () async {
    for (final state in ['cancelled', 'ended', 'connected']) {
      final port = Port()..state = state;
      await WakeRecovery(port, clock: () => now).receive(hint());
      expect(port.registrations, 0);
      expect(port.stages, ['received']);
    }
    final port = Port()..winner = 'other';
    await WakeRecovery(port, clock: () => now).receive(hint());
    expect(port.registrations, 0);
  });
  test(
    'Concurrent duplicate pushes share one registration and cancellation wins',
    () async {
      final port = Port()..registrationGate = Completer<void>();
      final recovery = WakeRecovery(port, clock: () => now);
      final first = recovery.receive(hint());
      final second = recovery.receive(hint());
      await Future<void>.delayed(Duration.zero);
      port.state = 'cancelled';
      port.registrationGate!.complete();
      await Future.wait([first, second]);
      expect(port.registrations, 1);
      expect(port.stages, ['received', 'restored']);
      await recovery.receive(hint());
      expect(port.registrations, 1);
    },
  );
  test(
    'Logout during recovery cannot emit registered for an obsolete session',
    () async {
      final port = Port()..registrationGate = Completer<void>();
      final recovery = WakeRecovery(port, clock: () => now);
      final pending = recovery.receive(hint());
      await Future<void>.delayed(Duration.zero);
      recovery.reset();
      port.registrationGate!.complete();
      await pending;
      expect(port.stages, isNot(contains('registered')));
    },
  );
  test(
    'Registration failure is reported separately from message receipt',
    () async {
      final port = Port()..registrationGate = Completer<void>();
      final recovery = WakeRecovery(port, clock: () => now);
      final pending = recovery.receive(hint());
      await Future<void>.delayed(Duration.zero);
      port.registrationGate!.completeError(TimeoutException('register'));
      await pending;
      expect(port.stages, ['received', 'restored', 'failed']);
    },
  );
}
