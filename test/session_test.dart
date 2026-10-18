import 'dart:async';
import 'package:homeline/core/networking/api_failure.dart';
import 'package:homeline/platform/call_integration/call_host.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:homeline/application/app_controller.dart';
import 'package:homeline/data/api/homeline_api.dart';
import 'package:homeline/data/dto/models.dart';
import 'package:homeline/data/local_database/local_store.dart';
import 'package:homeline/domain/calls/sip_service.dart';
import 'package:homeline/domain/queues/outbound_request.dart';
import 'package:homeline/infrastructure/server_events.dart';

import 'call_controller_test.dart'
    show TestSip, TestPlatform, event, serverCall;

class FakeHost extends CallHost {
  @override
  bool get supported => false;
  bool failClear = false;
  @override
  Future<void> clear() async {
    if (failClear) throw StateError('host unavailable');
  }
}

class FakeVault extends SessionVault {
  SessionDto? saved;
  @override
  Future<SessionDto?> read() async => saved;
  @override
  Future<void> save(SessionDto session) async {
    saved = session;
  }

  @override
  Future<void> clear() async {
    saved = null;
  }
}

class FakeStore extends LocalStore {
  OutboundRequest? intent;
  @override
  Future<OutboundRequest?> pending(String owner) async => intent;
  @override
  Future<void> saveIntent(String owner, OutboundRequest value) async {
    intent = value;
  }

  @override
  Future<void> resolveIntent(String owner) async {
    intent = null;
  }

  @override
  Future<void> clear() async {
    intent = null;
  }

  @override
  Future<void> close() async {}
}

class FakeEvents extends ServerEvents {
  String? lastToken;
  @override
  Future<void> start(
    String baseUrl,
    String token,
    void Function() invalidate,
  ) async {
    lastToken = token;
  }

  @override
  void stop() {}
}

class FakeApi extends HomeLineApi {
  FakeApi() : super('https://example.com');
  bool revoked = false, offline = false;
  SessionDto? restored;
  bool telemetryFails = false;
  Completer<CallDto>? resolveGate;
  @override
  Future<CallDto> callForSip(String sipId) async =>
      resolveGate == null ? serverCall() : await resolveGate!.future;
  @override
  Future<void> deviceEvent(String id, String stage, String key) async {
    if (telemetryFails) throw const ApiFailure('receipt unavailable');
  }

  @override
  Future<SessionDto> session() async {
    if (offline) throw const ApiFailure('offline');
    return restored!;
  }

  int loginCount = 0;
  Completer<SipCredentialsDto>? credentialGate;
  @override
  Future<SessionDto> login(String user, String password, String device) async =>
      SessionDto(
        accessToken: 'test-device-token-${++loginCount}',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        userId: 'server-user',
        extension: '1001',
        deviceId: 'server-device',
        accountStatus: 'active',
      );
  @override
  Future<SnapshotDto> snapshot() async => SnapshotDto(
    accountStatus: 'active',
    deviceStatus: revoked ? 'revoked' : 'active',
    lineStatus: 'idle',
    canCall: true,
    devices: [],
    calls: [],
    outboundTasks: [],
    history: [],
  );
  SipCredentialsDto get credentials => SipCredentialsDto(
    webSocketUrl: 'wss://example.com/ws',
    uri: 'sip:device@example.com',
    authorizationUser: 'device',
    password: 'test-secret',
    expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    iceServers: [],
  );
  @override
  Future<SipCredentialsDto> sipCredentials() async =>
      credentialGate == null ? credentials : await credentialGate!.future;
  @override
  Future<void> logout() async {}
  @override
  Future<void> updatePushToken(String? token) async {}
}

class CountingSip extends TestSip {
  final emittedCalls = StreamController<SipCallEvent>.broadcast();
  @override
  Stream<SipCallEvent> get callEvents => emittedCalls.stream;
  @override
  Future<void> dispose() => emittedCalls.close();
  int registrations = 0, stops = 0;
  Completer<void>? stopGate;
  @override
  Future<void> register(SipConfiguration configuration) async {
    registrations++;
  }

  @override
  Future<void> unregister() async {
    stops++;
    if (stopGate != null) await stopGate!.future;
  }
}

void main() {
  late FakeApi api;
  late FakeVault vault;
  late CountingSip sip;
  late TestPlatform platform;
  late AppController controller;
  late FakeEvents events;
  late FakeHost host;
  setUp(() {
    api = FakeApi();
    vault = FakeVault();
    sip = CountingSip();
    platform = TestPlatform();
    events = FakeEvents();
    host = FakeHost();
    controller = AppController(
      api: api,
      sip: sip,
      platform: platform,
      vault: vault,
      store: FakeStore(),
      serverEvents: events,
      callHost: host,
    );
  });
  tearDown(() {
    controller.dispose();
  });
  test(
    'Login binds server-issued user, device and personal extension',
    () async {
      await controller.login('user', 'password', 'phone');
      expect(controller.session!.userId, 'server-user');
      expect(controller.deviceId, 'server-device');
      expect(controller.session!.extension, '1001');
      expect(vault.saved, isNotNull);
      expect(sip.registrations, 1);
    },
  );
  test(
    'Device revocation stops local SIP and native call, clears credentials',
    () async {
      await controller.login('user', 'password', 'phone');
      await controller.calls.onSipEvent(event(CallPhase.ringing));
      api.revoked = true;
      await controller.refresh();
      expect(controller.session, isNull);
      expect(vault.saved, isNull);
      expect(sip.stops, greaterThan(0));
      expect(platform.ended, 1);
    },
  );
  test(
    'Logout while SIP credentials are loading cannot restart registration',
    () async {
      api.credentialGate = Completer<SipCredentialsDto>();
      final login = controller.login('user', 'password', 'phone');
      await Future<void>.delayed(Duration.zero);
      await controller.logout();
      api.credentialGate!.complete(api.credentials);
      await expectLater(login, throwsA(anything));
      expect(sip.registrations, 0);
      expect(controller.session, isNull);
    },
  );
  test(
    'Late login completion cannot replace a newer session event subscription',
    () async {
      final gate = Completer<SipCredentialsDto>();
      api.credentialGate = gate;
      final first = controller.login('user', 'password', 'phone');
      await Future<void>.delayed(Duration.zero);
      await controller.logout();
      api.credentialGate = null;
      await controller.login('user', 'password', 'new phone');
      final currentToken = controller.session!.accessToken;
      gate.complete(api.credentials);
      await expectLater(first, throwsStateError);
      expect(controller.session!.accessToken, currentToken);
      expect(events.lastToken, currentToken);
    },
  );
  test(
    'Offline restore retains secure session without fabricating registration',
    () async {
      vault.saved = await api.login('user', 'password', 'phone');
      api.offline = true;
      await controller.restore();
      expect(vault.saved, isNotNull);
      expect(controller.session, isNull);
      expect(sip.registrations, 0);
      api.offline = false;
      api.restored = vault.saved;
      await controller.restore();
      expect(controller.session!.deviceId, 'server-device');
      expect(sip.registrations, 1);
    },
  );
  test(
    'Native cleanup failure cannot retain session secrets after logout',
    () async {
      await controller.login('user', 'password', 'phone');
      host.failClear = true;
      await controller.logout();
      expect(vault.saved, isNull);
      expect(controller.session, isNull);
      expect(api.token, isNull);
      expect(sip.stops, greaterThan(0));
    },
  );
  test('Telemetry outage cannot end a real SIP and Telecom call', () async {
    await controller.login('user', 'password', 'phone');
    api.telemetryFails = true;
    sip.emittedCalls.add(event(CallPhase.ringing));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(platform.shown, 1);
    expect(sip.hangups, 0);
    sip.emittedCalls.add(event(CallPhase.active));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(platform.activated, 1);
    expect(controller.calls.current!.phase, CallPhase.active);
    expect(sip.hangups, 0);
    sip.emittedCalls.add(event(CallPhase.ended));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(platform.ended, 1);
  });
  test(
    'SIP cancellation clears Telecom while HTTP authorization is stalled',
    () async {
      await controller.login('user', 'password', 'phone');
      api.resolveGate = Completer<CallDto>();
      sip.emittedCalls.add(event(CallPhase.ringing));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      sip.emittedCalls.add(event(CallPhase.ended));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.calls.current!.terminal, isTrue);
      expect(platform.ended, 1);
      api.resolveGate!.complete(serverCall());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(platform.shown, 0);
      expect(controller.calls.current!.terminal, isTrue);
    },
  );
  test(
    'New login waits for old native cleanup and retains its new secure session',
    () async {
      await controller.login('user', 'password', 'phone');
      sip.stopGate = Completer<void>();
      final exiting = controller.logout();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.session, isNull);
      final entering = controller.login('user', 'password', 'new phone');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(api.loginCount, 1);
      sip.stopGate!.complete();
      await exiting;
      await entering;
      expect(api.loginCount, 2);
      expect(vault.saved!.accessToken, controller.session!.accessToken);
      expect(controller.session!.accessToken, 'test-device-token-2');
    },
  );
}
