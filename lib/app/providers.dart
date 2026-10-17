import 'package:flutter_riverpod/legacy.dart';

import '../application/app_controller.dart';
import '../data/api/homeline_api.dart';
import '../data/local_database/local_store.dart';
import '../infrastructure/sip/sip_ua_service.dart';
import '../platform/call_integration/call_integration.dart';

final appControllerProvider = ChangeNotifierProvider<AppController>((ref) {
  const endpoint = String.fromEnvironment('API_BASE_URL');
  return AppController(
    api: HomeLineApi(endpoint),
    sip: SipUaService(),
    platform: AndroidCallIntegration(),
    vault: const SessionVault(),
    store: LocalStore(),
  );
});
