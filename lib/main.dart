import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/networking/server_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? endpoint;
  try {
    endpoint = await ServerSettings.load();
  } catch (_) {}
  launch(endpoint);
}

void launch(String? endpoint) => runApp(
  endpoint != null
      ? ProviderScope(
          overrides: [apiEndpointProvider.overrideWithValue(endpoint)],
          child: const HomeLineApp(),
        )
      : const SetupRequiredApp(),
);
