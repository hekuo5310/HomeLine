import 'dart:io';

import 'package:homeline/core/networking/api_failure.dart';
import 'package:homeline/data/api/homeline_api.dart';

/// Real TLS handshake check. Generates an ephemeral, untrusted local certificate;
/// no test private key is committed or reused as a deployment credential.
Future<void> main() async {
  final temporary = await Directory.systemTemp.createTemp('homeline-tls-');
  HttpServer? server;
  HomeLineApi? api;
  try {
    final key = '${temporary.path}/key.pem';
    final cert = '${temporary.path}/cert.pem';
    final generated = await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      key,
      '-out',
      cert,
      '-days',
      '1',
      '-subj',
      '/CN=localhost',
      '-addext',
      'subjectAltName=DNS:localhost,IP:127.0.0.1',
    ]);
    if (generated.exitCode != 0) {
      throw StateError('OpenSSL certificate generation failed');
    }
    final context = SecurityContext()
      ..useCertificateChain(cert)
      ..usePrivateKey(key);
    server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    var requests = 0;
    server.listen(
      (request) {
        requests++;
        request.response.close();
      },
      onError: (Object _) {
        /* The peer rejects our untrusted certificate. */
      },
    );
    api = HomeLineApi('https://127.0.0.1:${server.port}');
    var rejected = false;
    try {
      await api.request('GET', '/v1/snapshot');
    } on ApiFailure {
      rejected = true;
    }
    if (!rejected || requests != 0) {
      throw StateError(
        'Untrusted TLS certificate was not rejected before HTTP',
      );
    }
    stdout.writeln(
      'PASS: real HTTPS handshake rejects an untrusted certificate before HTTP.',
    );
  } finally {
    api?.close();
    await server?.close(force: true);
    await temporary.delete(recursive: true);
  }
}
