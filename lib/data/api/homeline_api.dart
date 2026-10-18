import 'package:dio/dio.dart';

import '../../core/networking/api_failure.dart';
import '../dto/models.dart';

/// Implements docs/api-contract.md (PROPOSED, no backend exists in this repo).
class HomeLineApi {
  HomeLineApi(String endpoint, {Dio? client}) : dio = client ?? Dio() {
    final uri = Uri.parse(endpoint);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('服务器必须使用 HTTPS，不能包含用户信息、查询或片段');
    }
    dio.options = BaseOptions(
      baseUrl: endpoint.replaceFirst(RegExp(r'/+$'), ''),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      followRedirects: false,
      responseType: ResponseType.json,
    );
  }
  final Dio dio;
  String? token;
  void close() => dio.close(force: true);
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? data,
    String? idempotencyKey,
  }) async {
    try {
      final response = await dio.request<Map<String, dynamic>>(
        path,
        data: data,
        options: Options(
          method: method,
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            'Idempotency-Key': ?idempotencyKey,
          },
        ),
      );
      return response.data ?? <String, dynamic>{};
    } on DioException catch (e) {
      throw ApiFailure.fromDio(e);
    } on FormatException {
      throw const ApiFailure('服务器响应格式不兼容');
    }
  }

  Future<SessionDto> login(
    String username,
    String password,
    String deviceName,
  ) async => SessionDto.fromJson(
    await request(
      'POST',
      '/v1/sessions',
      data: {
        'username': username,
        'password': password,
        'device_name': deviceName,
        'platform': 'android',
      },
    ),
  );
  Future<SessionDto> session() async =>
      SessionDto.fromJson(await request('GET', '/v1/session'));
  Future<void> logout() async => request('DELETE', '/v1/session');
  Future<SnapshotDto> snapshot() async =>
      SnapshotDto.fromJson(await request('GET', '/v1/snapshot'));
  Future<SipCredentialsDto> sipCredentials() async =>
      SipCredentialsDto.fromJson(
        await request('POST', '/v1/devices/current/sip-credentials'),
      );
  Future<void> renameDevice(String id, String name) async => request(
    'PATCH',
    '/v1/devices/${Uri.encodeComponent(id)}',
    data: {'name': name},
  );
  Future<void> revokeDevice(String id, String key) async => request(
    'DELETE',
    '/v1/devices/${Uri.encodeComponent(id)}',
    idempotencyKey: key,
  );
  Future<void> updatePushToken(String? token) async => request(
    'PUT',
    '/v1/devices/current/push-token',
    data: {'provider': 'fcm', 'token': token},
  );
  Future<CallDto> callById(String id) async => CallDto.fromJson(
    await request('GET', '/v1/calls/${Uri.encodeComponent(id)}'),
  );
  Future<void> deviceEvent(String id, String stage, String key) async =>
      request(
        'POST',
        '/v1/calls/${Uri.encodeComponent(id)}/device-events',
        data: {'stage': stage},
        idempotencyKey: key,
      );
  Future<CallDto> callForSip(String sipId) async => CallDto.fromJson(
    await request('POST', '/v1/calls/resolve', data: {'sip_call_id': sipId}),
  );
  Future<CallDto> callAction(String id, String action, String key) async =>
      CallDto.fromJson(
        await request(
          'POST',
          '/v1/calls/${Uri.encodeComponent(id)}/$action',
          idempotencyKey: key,
        ),
      );
  Future<QueueTaskDto> submitOutbound(String number, String key) async =>
      QueueTaskDto.fromJson(
        await request(
          'POST',
          '/v1/outbound-tasks',
          data: {'destination': number},
          idempotencyKey: key,
        ),
      );
  Future<void> cancelTask(String id, String key) async => request(
    'POST',
    '/v1/outbound-tasks/${Uri.encodeComponent(id)}/cancel',
    idempotencyKey: key,
  );
}
