import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeline/application/app_controller.dart';
import 'package:homeline/data/api/homeline_api.dart';
import 'package:homeline/data/dto/models.dart';
import 'package:homeline/data/local_database/local_store.dart';
import 'package:homeline/domain/calls/sip_service.dart';
import 'package:homeline/domain/queues/outbound_request.dart';
import 'package:homeline/infrastructure/server_events.dart';
import 'call_controller_test.dart' show TestSip, TestPlatform, event;

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
  bool revoked = false;
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
  int registrations = 0, stops = 0;
  @override
  Future<void> register(SipConfiguration configuration) async {
    registrations++;
  }

  @override
  Future<void> unregister() async {
    stops++;
  }
}

void main() {
  late FakeApi api;
  late FakeVault vault;
  late CountingSip sip;
  late TestPlatform platform;
  late AppController controller;
  late FakeEvents events;
  setUp(() {
    api = FakeApi();
    vault = FakeVault();
    sip = CountingSip();
    platform = TestPlatform();
    events = FakeEvents();
    controller = AppController(
      api: api,
      sip: sip,
      platform: platform,
      vault: vault,
      store: FakeStore(),
      serverEvents: events,
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
}
