import 'dart:async';
import 'dart:io';

/// Events are invalidation hints; authenticated snapshots remain authoritative.
class ServerEvents {
  WebSocket? _socket;
  Timer? _retry;
  bool _stopped = true;
  int _generation = 0;
  Future<void> start(
    String baseUrl,
    String token,
    void Function() invalidate,
  ) async {
    stop();
    _stopped = false;
    final generation = _generation;
    Future<void> connect() async {
      if (_stopped || generation != _generation) return;
      try {
        final uri = Uri.parse('$baseUrl/v1/events').replace(scheme: 'wss');
        final socket = await WebSocket.connect(
          uri.toString(),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 10));
        if (_stopped || generation != _generation) {
          await socket.close();
          return;
        }
        _socket = socket;
        socket.pingInterval = const Duration(seconds: 20);
        socket.listen(
          (_) {
            invalidate();
          },
          onError: (Object _) {},
          onDone: () {
            if (!_stopped && generation == _generation) {
              _retry = Timer(const Duration(seconds: 5), connect);
            }
          },
          cancelOnError: true,
        );
        invalidate(); // Reconcile events missed during reconnect.
      } catch (_) {
        if (!_stopped && generation == _generation) {
          _retry = Timer(const Duration(seconds: 5), connect);
        }
      }
    }

    await connect();
  }

  void stop() {
    _stopped = true;
    _generation++;
    _retry?.cancel();
    unawaited(_socket?.close());
    _socket = null;
  }
}
