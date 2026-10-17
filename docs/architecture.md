# 架构与当前边界

这是可构建的客户端工程。后端未提供，真实 SIP、双设备、锁屏/FCM 和 FXO 尚未验收，不能作为已可用的家庭电话系统发布。

- `domain`：纯 Dart SIP 接口、通话事件、外呼意图；不依赖 Android/FCM。
- `application`：会话、权限租约、设备操作和通话仲裁。`CallController` 独立测试，服务器 claim 只授权应答，不产生 active。
- `data`：Dio API、checked json_serializable DTO、安全会话存储、SQLite 未确认外呼意图。数据库不保存 SIP 凭据或令牌。
- `infrastructure`：sip_ua 适配、FCM 提示、WebSocket 失效事件。SDK 全部 SIP 日志关闭。
- `platform`：Dart 内部接口/MethodChannel；Android Kotlin ConnectionService、CallStyle 通知与锁屏 Activity。
- `features`：Material 3 页面；Riverpod 管理控制器生命周期和状态，GoRouter 会话守卫。

服务器负责用户/个人分机/设备关联、PBX 注册与线路权限、原子接听、外呼串行调度和呼叫历史。一个用户可以有任意策略允许数量的设备，每设备独立认证，共享逻辑分机。客户端没有设备数量常量或 FXO 管理凭据。

Android 选择 API 26+ 自管理 ConnectionService（公开 Telecom 框架 API，无额外 AndroidX Telecom 依赖）。系统管理通话与音频仲裁，应用必须提供自己的原生通知/锁屏 UI。它不会自动出现默认拨号器的完整界面。API 34+ 使用 CallEndpoint，旧版使用 setAudioRoute，蓝牙可用性以实际设备回调为准。没有运行真机不能声称音频焦点、蓝牙或锁屏已验收。

跨平台边界保留；当前仅生成 Android 工程。sqflite 支持 Android/iOS/macOS；Windows 后续需要数据库适配，FCM 不适用于所有桌面平台。AndroidCallIntegration 在其他平台不声称提供系统通话能力。iOS CallKit/PushKit/APNs、Swift 与桌面系统集成均未实现。

Android 通话宿主：`HomeLineApplication` 下的 `CallEngine` 持有唯一 FlutterEngine；Activity 离开不销毁 SIP。`HomeMessagingService` 只持久化经过验证且最多 120 秒有效的 call_id 提示，不保存推送中的其他字段。高优先级 FCM 在系统允许时启动 phoneCall 前台服务，服务立即展示通知，短期 wakelock 支持恢复。Dart 恢复安全会话后才启用宿主提示消费；离线不会清除有效会话。服务根据真实 Telecom 通话、唤醒提示和 30 秒恢复租约结束，不在开机广播或 Application 中自动启动。

`WakeRecovery` 位于 Application，依赖纯 Dart `WakeHint` 与端口；相同呼叫并行恢复共用 Future，终止、过期和其他设备获胜不触发注册。流程核验服务器呼叫 → 恢复 SIP → 等待真实 REGISTER → 上报 registered → 等待真实 INVITE。HTTP 和推送均不能生成 active。重复/乱序服务器版本和迟到 SIP 终态由通话控制器处理；接听中仍可立即拒接。Telemetry 回执失败不挂断已经建立的真实通话。

活跃通话业务 ID 持久记录；进程重建只向服务器报告 media_lost 并核对历史，不伪造旧 RTP 会话已恢复。短期 SIP 凭据过期后拒绝新呼叫、取消注册，已有对话保留媒体；通话结束后重新获取凭据。权限租约丢失/账号撤销仍终止通话。Telecom 焦点被收回时结束当前单通话并释放焦点，不声称支持保持/恢复。锁屏号码默认隐藏，可在设置修改。

尚未完成的外部条件：服务端 API/PBX/FCM 项目配置、真机休眠/锁屏/音频验证、真实 FXO 队列验收。iOS 和桌面 runner/系统通话适配、联系人整合和历史分页属于后续工作。系统强制停止应用、降级 FCM、无 Google 服务或离线可能无法唤醒，服务器必须超时并进入备用路由；前台服务不能突破这些限制。

参考官方资料（2026-10-17 检查）：
- https://docs.flutter.dev/install/archive
- https://developer.android.com/reference/android/telecom/ConnectionService
- https://developer.android.com/reference/android/telecom/Connection
- https://developer.android.com/reference/android/telecom/TelecomManager
- https://developer.android.com/develop/connectivity/telecom/voip-app/telecom
- https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages
- https://github.com/flutter-webrtc/dart-sip-ua
- https://pub.dev/packages/sip_ua/versions/1.1.0

- https://developer.android.com/develop/background-work/services/fgs/service-types
- https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start
- https://firebase.google.com/docs/cloud-messaging/android/receive-messages
- https://firebase.google.com/docs/cloud-messaging/android-message-priority
