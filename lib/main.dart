import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const endpoint = String.fromEnvironment('API_BASE_URL');
  final uri = Uri.tryParse(endpoint);
  final configured =
      uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment;
  runApp(
    configured
        ? const ProviderScope(child: HomeLineApp())
        : const SetupRequiredApp(),
  );
}
