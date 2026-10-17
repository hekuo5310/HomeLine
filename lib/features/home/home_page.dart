import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../application/app_controller.dart';
import '../../domain/calls/sip_service.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({required this.tab, super.key});
  final int tab;
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _number = TextEditingController();
  Timer? _clock;
  static const paths = [
    '/',
    '/dialer',
    '/queues',
    '/devices',
    '/history',
    '/settings',
  ];
  static const labels = ['首页', '拨号', '排队', '设备', '记录', '设置'];
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final session = state.session;
    if (session == null) return const Scaffold();
    final snapshot = state.snapshot;
    final call = state.calls.current;
    return Scaffold(
      appBar: AppBar(
        title: Text('HomeLine · ${labels[widget.tab]}'),
        actions: [
          IconButton(
            onPressed: state.loading ? null : () => state.run(state.refresh),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.tab,
        onDestinationSelected: (index) => context.go(paths[index]),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
          NavigationDestination(icon: Icon(Icons.dialpad), label: '拨号'),
          NavigationDestination(
            icon: Icon(Icons.format_list_numbered),
            label: '排队',
          ),
          NavigationDestination(icon: Icon(Icons.devices), label: '设备'),
          NavigationDestination(icon: Icon(Icons.history), label: '记录'),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: '设置',
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (state.error != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(state.error!),
                  ),
                ),
              if (state.calls.outcome != null) Text(state.calls.outcome!),
              if (call != null && !call.terminal)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          call.incoming ? '来电' : '呼出',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          call.remote,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(_phase(call.phase)),
                        if (state.calls.connectedAt != null)
                          Text(
                            _duration(
                              DateTime.now().difference(
                                state.calls.connectedAt!,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            if (call.incoming &&
                                call.phase == CallPhase.ringing)
                              FilledButton(
                                onPressed: state.loading
                                    ? null
                                    : () => state.run(
                                        () => state.answer(call.id),
                                      ),
                                child: const Text('接听'),
                              ),
                            OutlinedButton(
                              onPressed: state.loading
                                  ? null
                                  : () => state.run(
                                      () => state.endCall(
                                        call.id,
                                        call.phase == CallPhase.ringing,
                                      ),
                                    ),
                              child: Text(
                                call.phase == CallPhase.ringing ? '拒接' : '挂断',
                              ),
                            ),
                            if (call.phase == CallPhase.active) ...[
                              OutlinedButton(
                                onPressed: state.loading
                                    ? null
                                    : () => state.run(
                                        () => state.setMuted(!state.muted),
                                      ),
                                child: Text(state.muted ? '取消静音' : '静音'),
                              ),
                              for (final route in [
                                ('earpiece', '听筒'),
                                ('speaker', '扬声器'),
                                ('bluetooth', '蓝牙'),
                              ])
                                OutlinedButton(
                                  onPressed: state.loading
                                      ? null
                                      : () => state.run(
                                          () => state.route(route.$1),
                                        ),
                                  child: Text(route.$2),
                                ),
                            ],
                          ],
                        ),
                        Text('音频路由：${state.audioRoute}'),
                      ],
                    ),
                  ),
                ),
              ...switch (widget.tab) {
                0 => <Widget>[
                  Text(
                    '分机 ${session.extension}',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 16),
                  _row('SIP', switch (state.registration) {
                    SipRegistrationState.stopped => '已停止',
                    SipRegistrationState.connecting => '连接中',
                    SipRegistrationState.registered => '已注册',
                    SipRegistrationState.failed => '注册失败',
                  }),
                  _row('外线', snapshot?.lineStatus ?? '尚未同步'),
                  _row(
                    '待处理外呼',
                    '${snapshot?.outboundTasks.where((t) => t.state == 'waiting').length ?? 0}',
                  ),
                  const Divider(),
                  const Text('一条模拟固话通常只能同时进行一通外线电话。'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => context.go('/dialer'),
                    child: const Text('拨打电话'),
                  ),
                ],
                1 => _dialer(state),
                2 => <Widget>[
                  Text('外部来电', style: Theme.of(context).textTheme.titleLarge),
                  for (final c in snapshot?.calls ?? [])
                    ListTile(
                      title: Text(c.remote),
                      subtitle: Text(
                        '${c.state}${c.queuePosition == null ? '' : ' · 位置 ${c.queuePosition}'}${c.waitingSince == null ? '' : ' · 已等待 ${_duration(DateTime.now().difference(c.waitingSince!))}'}',
                      ),
                    ),
                  const Divider(),
                  Text('外呼任务', style: Theme.of(context).textTheme.titleLarge),
                  for (final task in snapshot?.outboundTasks ?? [])
                    ListTile(
                      title: Text(task.destination),
                      subtitle: Text(
                        '${task.state}${task.position == null ? '' : ' · 位置 ${task.position}'}${task.estimatedWaitSeconds == null ? '' : ' · 预计 ${task.estimatedWaitSeconds} 秒'}${task.failureReason == null ? '' : ' · ${task.failureReason}'}',
                      ),
                      trailing: task.state == 'waiting'
                          ? TextButton(
                              onPressed: state.loading
                                  ? null
                                  : () =>
                                        state.run(() => state.cancelTask(task)),
                              child: const Text('取消'),
                            )
                          : null,
                    ),
                  if (snapshot == null) const Text('尚未获得服务器队列数据'),
                ],
                3 => <Widget>[
                  Text(
                    '设备策略：${session.deviceLimit == null ? '由管理员管理，未返回数量上限' : '最多 ${session.deviceLimit} 台'}',
                  ),
                  for (final device in snapshot?.devices ?? [])
                    ListTile(
                      title: Text(
                        '${device.name}${device.id == session.deviceId ? '（本机）' : ''}',
                      ),
                      subtitle: Text(
                        '${device.status} · ${device.lastSeenAt.toLocal()}',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) async {
                          if (action == 'rename') {
                            final name = TextEditingController(
                              text: device.name,
                            );
                            final value = await showDialog<String>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('设备名称'),
                                content: TextField(
                                  controller: name,
                                  maxLength: 80,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext),
                                    child: const Text('取消'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, name.text),
                                    child: const Text('保存'),
                                  ),
                                ],
                              ),
                            );
                            // Dialog route disposes its field after its closing animation.
                            Future<void>.delayed(
                              const Duration(seconds: 1),
                              name.dispose,
                            );
                            if (value != null) {
                              await state.run(
                                () => state.renameDevice(device, value),
                              );
                            }
                          } else {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: Text('撤销 ${device.name}？'),
                                content: const Text('此设备将不能继续注册或接听。'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, false),
                                    child: const Text('取消'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, true),
                                    child: const Text('撤销'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await state.run(() => state.revoke(device));
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'rename', child: Text('重命名')),
                          PopupMenuItem(value: 'revoke', child: Text('撤销')),
                        ],
                      ),
                    ),
                ],
                4 => <Widget>[
                  for (final c in snapshot?.history ?? [])
                    ListTile(
                      title: Text(c.remote),
                      subtitle: Text('${c.state} · ${c.updatedAt.toLocal()}'),
                    ),
                  if (snapshot?.history.isEmpty ?? true)
                    const Text('暂无服务器通话记录'),
                ],
                _ => <Widget>[
                  _row('账号', session.userId),
                  _row('分机', session.extension),
                  _row('推送', state.pushStatus),
                  _row('API', state.api.dio.options.baseUrl),
                  const Text(
                    '休眠来电尚未完成；请保持应用前台进行 SIP 技术验证。\n未验证 iOS / Windows / macOS。',
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: state.loading
                        ? null
                        : () => state.run(state.configureTelecom),
                    child: const Text('启用 Android 系统通话账号'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: state.loading
                        ? null
                        : () => state.run(state.logout),
                    child: const Text('退出登录'),
                  ),
                ],
              },
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _dialer(AppController state) => [
    TextField(
      controller: _number,
      keyboardType: TextInputType.phone,
      decoration: const InputDecoration(labelText: '分机或外线号码'),
    ),
    const SizedBox(height: 16),
    for (final row in ['123', '456', '789', '*0#'])
      Row(
        children: [
          for (final digit in row.split(''))
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: OutlinedButton(
                  onPressed: () {
                    _number.text += digit;
                  },
                  child: Text(digit, style: const TextStyle(fontSize: 24)),
                ),
              ),
            ),
        ],
      ),
    Align(
      alignment: Alignment.centerRight,
      child: IconButton(
        tooltip: '删除',
        icon: const Icon(Icons.backspace_outlined),
        onPressed: () {
          if (_number.text.isNotEmpty) {
            _number.text = _number.text.substring(0, _number.text.length - 1);
          }
        },
      ),
    ),
    FilledButton(
      onPressed: !state.canCall || state.loading
          ? null
          : () => state.run(() => state.dial(_number.text)),
      child: const Text('拨打个人分机'),
    ),
    const SizedBox(height: 12),
    OutlinedButton(
      onPressed: !state.canCall || state.loading
          ? null
          : () => state.run(() => state.outbound(_number.text)),
      child: const Text('提交外线排队'),
    ),
    if (state.pendingOutbound != null)
      TextButton(
        onPressed: state.loading
            ? null
            : () => state.run(
                () => state.outbound(state.pendingOutbound!.destination),
              ),
        child: Text('重试未确认请求：${state.pendingOutbound!.destination}（复用同一请求编号）'),
      ),
  ];
  Widget _row(String title, String value) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(value),
  );
  String _phase(CallPhase phase) => switch (phase) {
    CallPhase.ringing => '振铃中',
    CallPhase.dialing => '拨号中',
    CallPhase.connecting => '连接中',
    CallPhase.active => '通话中',
    CallPhase.ended => '已结束',
    CallPhase.failed => '失败',
  };
  String _duration(Duration value) {
    final seconds = value.inSeconds.clamp(0, 999999);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
