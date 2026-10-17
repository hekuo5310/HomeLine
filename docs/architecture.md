# 架构与当前边界

这是第一阶段可构建的客户端工程。后端未提供，真实 SIP、双设备、锁屏/FCM 和 FXO 尚未验收，不能作为已可用的家庭电话系统发布。

- `domain`：纯 Dart SIP 接口、通话事件、外呼意图；不依赖 Android/FCM。
- `application`：会话、权限租约、设备操作和通话仲裁。`CallController` 独立测试，服务器 claim 只授权应答，不产生 active。
- `data`：Dio API、checked json_serializable DTO、安全会话存储、SQLite 未确认外呼意图。数据库不保存 SIP 凭据或令牌。
- `infrastructure`：sip_ua 适配、FCM 提示、WebSocket 失效事件。SDK 全部 SIP 日志关闭。
- `platform`：Dart 内部接口/MethodChannel；Android Kotlin ConnectionService、CallStyle 通知与锁屏 Activity。
- `features`：Material 3 页面；Riverpod 管理控制器生命周期和状态，GoRouter 会话守卫。

服务器负责用户/个人分机/设备关联、PBX 注册与线路权限、原子接听、外呼串行调度和呼叫历史。一个用户可以有任意策略允许数量的设备，每设备独立认证，共享逻辑分机。客户端没有设备数量常量或 FXO 管理凭据。

Android 选择 API 26+ 自管理 ConnectionService（公开 Telecom 框架 API，无额外 AndroidX Telecom 依赖）。系统管理通话与音频仲裁，应用必须提供自己的原生通知/锁屏 UI。它不会自动出现默认拨号器的完整界面。API 34+ 使用 CallEndpoint，旧版使用 setAudioRoute，蓝牙可用性以实际设备回调为准。没有运行真机不能声称音频焦点、蓝牙或锁屏已验收。

跨平台边界保留；当前仅生成 Android 工程。sqflite 支持 Android/iOS/macOS；Windows 后续需要数据库适配，FCM 不适用于所有桌面平台。AndroidCallIntegration 在其他平台不声称提供系统通话能力。iOS CallKit/PushKit/APNs、Swift 与桌面系统集成均未实现。

尚未完成：headless/native FlutterEngine 来电恢复、后台音频前台服务与进程死亡恢复、FCM 回执与重试诊断、服务端 API 实现、自动化 PBX/FXO 集成、发布签名、完整联系人和历史分页。当前 FCM background isolate 仅保存唤醒提示，必须保持应用前台进行 SIP 技术验证。切到后台/锁屏不能保证持续通话或来电；不能通过 WebSocket/poll 代替移动推送验证。

参考官方资料（2026-10-17 检查）：
- https://docs.flutter.dev/install/archive
- https://developer.android.com/reference/android/telecom/ConnectionService
- https://developer.android.com/reference/android/telecom/Connection
- https://developer.android.com/reference/android/telecom/TelecomManager
- https://developer.android.com/develop/connectivity/telecom/voip-app/telecom
- https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages
- https://github.com/flutter-webrtc/dart-sip-ua
- https://pub.dev/packages/sip_ua/versions/1.1.0
