import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/home/home_page.dart';
import 'providers.dart';
import 'theme.dart';

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

class SetupRequiredApp extends StatelessWidget {
  const SetupRequiredApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: homeLineTheme(),
    home: Scaffold(
      appBar: AppBar(title: const Text('HomeLine')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '尚未配置电话服务器。\n请按照 README 配置 HTTPS API 地址。\n\n当前版本不会模拟注册、来电或接通。',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
