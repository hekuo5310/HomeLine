import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _username = TextEditingController(),
      _password = TextEditingController();
  final _device = TextEditingController(text: '我的 Android 手机');
  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _device.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('HomeLine')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text('连接家庭电话', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              const Text('使用电话服务器账号登录，每台设备独立认证。'),
              const SizedBox(height: 24),
              TextField(
                controller: _username,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: '密码'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _device,
                decoration: const InputDecoration(labelText: '本机设备名称'),
              ),
              const SizedBox(height: 24),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    state.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: state.loading
                    ? null
                    : () async {
                        await state.run(
                          () => state.login(
                            _username.text,
                            _password.text,
                            _device.text,
                          ),
                        );
                        _password.clear();
                      },
                child: Text(state.loading ? '登录中…' : '登录'),
              ),
              const SizedBox(height: 16),
              const Text('后端契约尚需实现；Android 休眠来电恢复未完成。'),
            ],
          ),
        ),
      ),
    );
  }
}
