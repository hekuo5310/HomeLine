import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeline/data/api/homeline_api.dart';
import 'package:homeline/core/networking/api_failure.dart';
import 'package:homeline/domain/queues/outbound_request.dart';
import 'package:homeline/infrastructure/push/push_service.dart';

class CaptureAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  int status = 200;
  String body = '{}';
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  test('API requires TLS and rejects credential/query based configuration', () {
    for (final endpoint in [
      'http://example.com',
      'https://user:pass@example.com',
      'https://example.com?token=x',
    ]) {
      expect(() => HomeLineApi(endpoint), throwsFormatException);
    }
  });
  test(
    'Retries keep authorization and idempotency headers, no redirects',
    () async {
      final adapter = CaptureAdapter();
      final api = HomeLineApi(
        'https://example.com',
        client: Dio()..httpClientAdapter = adapter,
      );
      api.token = 'test-token';
      final intent = OutboundRequest('+86123456789');
      await api.request(
        'POST',
        '/v1/outbound-tasks',
        data: {'destination': intent.destination},
        idempotencyKey: intent.idempotencyKey,
      );
      await api.request(
        'POST',
        '/v1/outbound-tasks',
        data: {'destination': intent.destination},
        idempotencyKey: intent.idempotencyKey,
      );
      expect(
        adapter.requests[0].headers['Idempotency-Key'],
        adapter.requests[1].headers['Idempotency-Key'],
      );
      expect(adapter.requests[0].headers['Authorization'], 'Bearer test-token');
      expect(adapter.requests[0].followRedirects, false);
      api.close();
    },
  );
  test(
    'Unauthorized and conflict responses preserve actionable status',
    () async {
      final adapter = CaptureAdapter();
      final api = HomeLineApi(
        'https://example.com',
        client: Dio()..httpClientAdapter = adapter,
      );
      for (final status in [401, 403, 409]) {
        adapter.status = status;
        await expectLater(
          api.request('GET', '/v1/snapshot'),
          throwsA(
            isA<ApiFailure>().having((e) => e.statusCode, 'status', status),
          ),
        );
      }
      api.close();
    },
  );
  test('Untrusted push hints expire and cannot represent SIP state', () {
    final now = DateTime.utc(2026, 10, 17);
    Map<String, dynamic> hint(DateTime expiration) => {
      'type': 'incoming_call',
      'call_id': 'c1',
      'expires_at': expiration.toIso8601String(),
    };
    expect(WakeHint.parse(hint(now), now), isNull);
    expect(
      WakeHint.parse(hint(now.add(const Duration(hours: 1))), now),
      isNull,
    );
    expect(
      WakeHint.parse(hint(now.add(const Duration(seconds: 30))), now)?.callId,
      'c1',
    );
    expect(WakeHint.parse({'type': 'connected', 'call_id': 'c1'}, now), isNull);
  });
  test('Outbound input rejects SIP URI injection and invalid numbers', () {
    for (final value in ['sip:1001@evil.example', '1', '123\r\nX-Test:1']) {
      expect(() => OutboundRequest(value), throwsFormatException);
    }
    final first = OutboundRequest('12345');
    final restored = OutboundRequest.restore(
      first.destination,
      first.idempotencyKey,
    );
    expect(restored.idempotencyKey, first.idempotencyKey);
  });
}
