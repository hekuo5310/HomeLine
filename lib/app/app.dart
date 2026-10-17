import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/home/home_page.dart';
import 'providers.dart';
import 'theme.dart';
import '../main.dart' show launch;
import '../core/networking/server_settings.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final controller = ref.read(appControllerProvider);
  final router = GoRouter(
    refreshListenable: controller,
    initialLocation: '/',
    redirect: (context, state) {
      if (controller.restoring) {
        return state.matchedLocation == '/loading' ? null : '/loading';
      }
      if (controller.session == null) {
        return state.matchedLocation == '/login' ? null : '/login';
      }
      if (state.matchedLocation == '/login' ||
          state.matchedLocation == '/loading') {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/loading',
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/', builder: (_, _) => const HomePage(tab: 0)),
      GoRoute(path: '/dialer', builder: (_, _) => const HomePage(tab: 1)),
      GoRoute(path: '/queues', builder: (_, _) => const HomePage(tab: 2)),
      GoRoute(path: '/devices', builder: (_, _) => const HomePage(tab: 3)),
      GoRoute(path: '/history', builder: (_, _) => const HomePage(tab: 4)),
      GoRoute(path: '/settings', builder: (_, _) => const HomePage(tab: 5)),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class HomeLineApp extends ConsumerStatefulWidget {
  const HomeLineApp({super.key});
  @override
  ConsumerState<HomeLineApp> createState() => _HomeLineAppState();
}

class _HomeLineAppState extends ConsumerState<HomeLineApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => ref.read(appControllerProvider).restore());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(appControllerProvider).refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'HomeLine',
    theme: homeLineTheme(),
    routerConfig: ref.watch(routerProvider),
  );
}

class SetupRequiredApp extends StatefulWidget {
  const SetupRequiredApp({super.key});
  @override
  State<SetupRequiredApp> createState() => _SetupRequiredAppState();
}

class _SetupRequiredAppState extends State<SetupRequiredApp> {
  final server = TextEditingController();
  String? error;
  bool saving = false;
  @override
  void dispose() {
    server.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: homeLineTheme(),
    home: Scaffold(
      appBar: AppBar(title: const Text('HomeLine')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Text('尚未配置电话服务器。请输入自建服务器的 HTTPS 地址。'),
              const SizedBox(height: 20),
              TextField(
                controller: server,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'HTTPS 服务器地址'),
              ),
              if (error != null) Text(error!),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        setState(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          final value = server.text.trim();
                          await ServerSettings.save(value);
                          launch(value);
                        } catch (_) {
                          if (mounted) {
                            setState(() {
                              error = '地址无效或安全存储不可用，请检查 HTTPS 地址';
                              saving = false;
                            });
                          }
                        }
                      },
                child: const Text('连接服务器'),
              ),
              const SizedBox(height: 12),
              const Text('服务器负责账号、分机和线路授权。应用不会模拟注册或通话。'),
            ],
          ),
        ),
      ),
    ),
  );
}
