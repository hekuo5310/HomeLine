import 'dart:async';
import 'package:homeline/core/networking/api_failure.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeline/application/call_controller.dart';
import 'package:homeline/domain/calls/sip_service.dart';
import 'package:homeline/data/dto/models.dart';
import 'package:homeline/platform/call_integration/call_integration.dart';

class TestSip implements SipService {
  int answers = 0, hangups = 0;
  @override
  Future<void> answer(String id) async {
    answers++;
  }

  @override
  Future<void> hangup(String id) async {
    hangups++;
  }

  @override
  Future<void> reject(String id) async {
    hangups++;
  }

  @override
  Future<void> dial(String destination) async {}
  @override
  Future<void> register(SipConfiguration configuration) async {}
  @override
  Future<void> unregister() async {}
  @override
  Future<void> mute(String id, bool muted) async {}
  @override
  Future<void> dispose() async {}
  @override
  Stream<SipCallEvent> get callEvents => const Stream.empty();
  @override
  Stream<SipRegistrationState> get registrationStates => const Stream.empty();
}

class TestPlatform implements CallIntegration {
  int shown = 0, activated = 0, ended = 0;
  @override
  Future<void> show(String id, String remote, bool incoming) async {
    shown++;
  }

  @override
  Future<void> active(String id) async {
    activated++;
  }

  @override
  Future<void> end(String id) async {
    ended++;
  }

  @override
  Future<void> configure() async {}
  @override
  Future<void> route(String id, String route) async {}
  @override
  Stream<Map<String, dynamic>> get actions => const Stream.empty();
}

CallDto serverCall({
  String? winner,
  String state = 'ringing',
  int revision = 1,
}) => CallDto(
  id: 'server-call',
  sipCallId: 'wire-id',
  state: state,
  remote: '1001',
  updatedAt: DateTime.utc(2026),
  revision: revision,
  answeredDeviceId: winner,
);

class Authority implements CallAuthority {
  @override
  String get deviceId => 'this-device';
  CallDto result = serverCall(winner: 'this-device');
  Completer<CallDto>? gate;
  int claims = 0;
  bool conflict = false;
  @override
  Future<CallDto> resolve(String id) async => serverCall();
  @override
  Future<CallDto> claim(String id, String key) async {
    claims++;
    if (conflict) throw const ApiFailure('Already claimed', statusCode: 409);
    return gate == null ? result : await gate!.future;
  }

  @override
  Future<CallDto> action(String id, String action, String key) async => result;
}

SipCallEvent event(CallPhase phase) =>
    SipCallEvent(id: 'wire-id', phase: phase, incoming: true, remote: '1001');
void main() {
  late TestSip sip;
  late TestPlatform platform;
  late Authority authority;
  late CallController controller;
  setUp(() {
    sip = TestSip();
    platform = TestPlatform();
    authority = Authority();
    controller = CallController(sip, platform, authority);
  });
  test(
    'Duplicate ringing creates one native call; HTTP claim never activates',
    () async {
      await controller.onSipEvent(event(CallPhase.ringing));
      await controller.onSipEvent(event(CallPhase.ringing));
      await controller.answer('wire-id', 'key');
      expect(platform.shown, 1);
      expect(sip.answers, 1);
      expect(platform.activated, 0);
      await controller.onSipEvent(event(CallPhase.active));
      expect(platform.activated, 1);
      expect(controller.connectedAt, isNotNull);
      await controller.onSipEvent(event(CallPhase.ringing));
      expect(controller.current!.phase, CallPhase.active);
    },
  );
  test('Another device wins and late SIP cannot resurrect the call', () async {
    await controller.onSipEvent(event(CallPhase.ringing));
    authority.result = serverCall(winner: 'another');
    await controller.answer('wire-id', 'key');
    await controller.onSipEvent(event(CallPhase.active));
    expect(sip.answers, 0);
    expect(sip.hangups, 2);
    expect(platform.activated, 0);
    expect(controller.outcome, contains('其他设备'));
  });
  test('Cancellation while claim is in flight blocks a stale answer', () async {
    await controller.onSipEvent(event(CallPhase.ringing));
    authority.gate = Completer<CallDto>();
    final answer = controller.answer('wire-id', 'key');
    await Future<void>.delayed(Duration.zero);
    await controller.applyServerCall(
      serverCall(state: 'cancelled', revision: 3),
    );
    authority.gate!.complete(serverCall(winner: 'this-device', revision: 2));
    await answer;
    expect(sip.answers, 0);
  });
  test('Repeated answer taps issue one claim', () async {
    await controller.onSipEvent(event(CallPhase.ringing));
    authority.gate = Completer<CallDto>();
    final first = controller.answer('wire-id', 'key');
    final second = controller.answer('wire-id', 'key');
    await Future<void>.delayed(Duration.zero);
    authority.gate!.complete(serverCall(winner: 'this-device'));
    await Future.wait([first, second]);
    expect(authority.claims, 1);
  });
  test('Older server revisions cannot regress terminal state', () async {
    await controller.applyServerCall(serverCall(state: 'ended', revision: 5));
    await controller.applyServerCall(serverCall(revision: 2));
    await controller.onSipEvent(event(CallPhase.ringing));
    expect(platform.shown, 0);
  });
  test(
    'TLS transport configuration rejects plaintext or embedded credentials',
    () {
      for (final uri in [
        'ws://example.com/ws',
        'tcp://example.com',
        'wss://user:pass@example.com',
      ]) {
        expect(
          () => SipConfiguration(
            webSocketUrl: uri,
            uri: 'sip:device@example.com',
            authorizationUser: 'device',
            password: 'test',
            expiresAt: DateTime.utc(2099),
          ),
          throwsFormatException,
        );
      }
    },
  );
  test('HTTP 409 stops native ringing and never answers SIP', () async {
    await controller.onSipEvent(event(CallPhase.ringing));
    authority.conflict = true;
    await expectLater(
      controller.answer('wire-id', 'key'),
      throwsA(isA<ApiFailure>()),
    );
    expect(sip.answers, 0);
    expect(platform.ended, 1);
    expect(controller.current!.terminal, true);
  });
  test('Logout during claim makes the in-flight response unusable', () async {
    await controller.onSipEvent(event(CallPhase.ringing));
    authority.gate = Completer<CallDto>();
    final answer = controller.answer('wire-id', 'key');
    await Future<void>.delayed(Duration.zero);
    controller.reset();
    authority.gate!.complete(serverCall(winner: 'this-device'));
    await answer;
    expect(sip.answers, 0);
    expect(controller.current, isNull);
  });
}
