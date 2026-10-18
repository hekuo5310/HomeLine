import 'package:dio/dio.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  bool get invalidSession => statusCode == 401 || statusCode == 403;
  @override
  String toString() => message;
  factory ApiFailure.fromDio(DioException e) {
    final status = e.response?.statusCode;
    return ApiFailure(switch (status) {
      401 => '登录已过期，请重新登录',
      403 => '账号已禁用、设备已撤销或没有权限',
      409 => '状态已变化，请刷新；可能已被其他设备接听',
      429 => '请求过于频繁，请稍后再试',
      _ =>
        e.type == DioExceptionType.badCertificate
            ? 'TLS 证书验证失败，连接已拒绝'
            : '服务器不可用或请求失败，请检查网络后重试',
    }, statusCode: status);
  }
}
