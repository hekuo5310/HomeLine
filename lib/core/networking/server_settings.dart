import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ServerSettings {
  static const _storage = FlutterSecureStorage();
  static bool valid(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  static Future<String?> load() async {
    const compiled = String.fromEnvironment('API_BASE_URL');
    if (valid(compiled)) return compiled;
    final stored = await _storage.read(key: 'server_url');
    return stored != null && valid(stored) ? stored : null;
  }

  static Future<void> save(String value) async {
    if (!valid(value)) throw const FormatException('请输入有效 HTTPS 服务器地址');
    await _storage.write(
      key: 'server_url',
      value: value.replaceFirst(RegExp(r'/+$'), ''),
    );
  }
}
