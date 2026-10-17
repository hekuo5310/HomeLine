import 'dart:async';

enum SipRegistrationState { stopped, connecting, registered, failed, expired }

enum CallPhase { ringing, dialing, connecting, active, ended, failed }

class SipCallEvent {
  const SipCallEvent({
    required this.id,
    required this.phase,
    required this.incoming,
    required this.remote,
    this.reason,
  });
  final String id;
  final CallPhase phase;
  final bool incoming;
  final String remote;
  final String? reason;
  bool get terminal => phase == CallPhase.ended || phase == CallPhase.failed;
}

class SipConfiguration {
  SipConfiguration({
    required this.webSocketUrl,
    required this.uri,
    required this.authorizationUser,
    required this.password,
    required this.expiresAt,
    this.iceServers = const [],
  }) {
    final ws = Uri.parse(webSocketUrl);
    if (ws.scheme != 'wss' || ws.host.isEmpty || ws.userInfo.isNotEmpty) {
      throw const FormatException('SIP requires a valid WSS endpoint');
    }
    if (!uri.startsWith('sip:') || !uri.contains('@')) {
      throw const FormatException('Invalid device SIP URI');
    }
  }
  final String webSocketUrl, uri, authorizationUser, password;
  final DateTime expiresAt;
  final List<Map<String, String>> iceServers;
}

abstract interface class SipService {
  Future<void> register(SipConfiguration configuration);
  Future<void> unregister();
  Future<void> dial(String destination);
  Future<void> answer(String callId);
  Future<void> reject(String callId);
  Future<void> hangup(String callId);
  Future<void> mute(String callId, bool muted);
  Stream<SipRegistrationState> get registrationStates;
  Stream<SipCallEvent> get callEvents;
  Future<void> dispose();
}
