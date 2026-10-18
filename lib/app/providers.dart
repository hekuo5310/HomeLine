import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/app_controller.dart';
import '../data/api/homeline_api.dart';
import '../data/local_database/local_store.dart';
import '../infrastructure/sip/sip_ua_service.dart';
import '../platform/call_integration/call_integration.dart';

final apiEndpointProvider = Provider<String>(
  (ref) => const String.fromEnvironment('API_BASE_URL'),
);

final appControllerProvider = ChangeNotifierProvider<AppController>((ref) {
  final endpoint = ref.watch(apiEndpointProvider);
  return AppController(
    api: HomeLineApi(endpoint),
    sip: SipUaService(),
    platform: AndroidCallIntegration(),
    vault: const SessionVault(),
    store: LocalStore(),
  );
});
