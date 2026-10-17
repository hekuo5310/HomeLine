# 依赖选择与维护核查

2026-10-17 从 pub.dev 官方 package API、许可证页面和 sip_ua 1.1.0 发布归档核查；最终可安装版本以 `pubspec.lock` 和构建结果为准。使用 MIT/BSD 组件并保留本项目 MPL-2.0，不引入需要另行购买商用许可的 SIP SDK。

| 组件 | 指定版本 | 许可证 | 平台/限制 |
|---|---|---|---|
| Flutter | 3.47.7 stable | BSD-3-Clause | 当前生成 Android runner；其他 runner 未来添加 |
| flutter_riverpod | 3.4.3 | MIT | Flutter 多平台；使用官方 legacy ChangeNotifierProvider 适配现有 Listenable |
| go_router | 18.1.0 | BSD-3-Clause | Flutter 多平台 |
| dio | 5.11.1 | MIT | Dart 多平台，默认验证 TLS，禁止重定向 |
| json_annotation | 4.12.0 | BSD-3-Clause | DTO 注解，checked 反序列化 |
| json_serializable | 6.14.1 | BSD-3-Clause | 开发期生成 |
| build_runner | 2.16.2 | BSD-3-Clause | 开发期；2.17.1 的 build 5 约束与上述生成器不兼容 |
| flutter_secure_storage | 11.2.0 | BSD-3-Clause | Android Keystore / iOS Keychain 等；需分别验证各 runner 配置 |
| sqflite | 2.4.4+2 | BSD-2-Clause | Android/iOS/macOS；Windows 需未来实现 |
| firebase_core | 5.0.0 | BSD-3-Clause | FlutterFire；需要自己的 Firebase 项目 |
| firebase_messaging | 17.0.0 | BSD-3-Clause | Android/iOS/macOS/Web；不是 Windows 推送方案 |
| permission_handler | 12.0.3 | MIT | Android 实现 13.0.1，compileSdk 35，可用于本工程 SDK 36 |
| uuid | 4.6.0 | MIT | Dart；幂等请求编号，不作为设备身份认证 |
| sip_ua | 1.1.0 | MIT | Android/iOS/桌面/Web；WSS/WebRTC，非原生 5061 SIP TLS |
| flutter_webrtc | 1.6.2+hotfix.4 | MIT | 原生 WebRTC 媒体；实际平台音频行为需验收 |
| logger | 2.8.0 | MIT | 用于关闭 SIP SDK 原始日志，避免认证内容外泄 |
| flutter_lints | 6.0.0 | BSD-3-Clause | 开发期 |

以上组件均有官方发布页/维护仓库，所选版本发布归档可审计。JSON 工具、Flutter lint 有意按 SDK 兼容性锁定；不因存在更高版本就忽略约束强行升级。`pubspec.lock` 固定传递依赖及 SHA256；发布前还需检查这些传递依赖的许可证，并通过 Flutter 内置许可页/发行材料保留 NOTICE。

核查入口：`https://pub.dev/packages/<package>/versions/<version>`、`https://pub.dev/api/packages/<package>`，以及各发布归档 LICENSE。SIP API 根据发布归档源码适配，而非把 README 的内部接口假定为真实 SDK API。

权限插件没有盲用最新版：13.0.2 解析到 Android 实现 14.1.0，要求 SDK 37；本工程选择已核实的 12.0.3 / Android 13.0.1 来保持 SDK 36 构建兼容。

Firebase Messaging 17 新增的 onRegistered 发出 Firebase Installation ID，契约 v1 则需要 FCM registration token。适配器明确保留该版本仍支持的 getToken/onTokenRefresh 兼容 API，不把 FID 冒充 token；未来必须与服务器寻址协议一起迁移。

## Android 原生新增依赖

- Google Services Gradle 插件 4.4.4（Google 官方；Apache-2.0）：仅本地存在 google-services.json 时应用。
- Firebase Android BoM 35.0.0 + firebase-messaging（Google 官方；Apache-2.0）：与 firebase_core 5.0.0 解析的 BoM 一致；具体原生版本由 BoM 固定。Android 使用原生 token 和 onNewToken，避免混用 Firebase Installation ID。FlutterFire 的三个后台组件从 Android manifest 合并结果移除，以免产生第二个 SIP 引擎/重复接收；保留 Google Firebase 接收器。
- JUnit 4.13.2（EPL-1.0）与 Robolectric 4.17（MIT）：仅 JVM 测试；不进入发布 APK。Robolectric 测试配置 Android API 35 与 JDK 17。

维护/许可核查入口：Firebase 官方 Android release notes、Google Services 插件文档、firebase-android-sdk LICENSE 与 Robolectric 4.17 GitHub release/LICENSE。原生编译和 WakeStore JVM 测试单独记录在 verification.md。Flutter 其余平台的 FlutterFire 路径仅为扩展边界，不代表已交付对应系统来电能力。

- https://firebase.google.com/support/release-notes/android
- https://developers.google.com/android/guides/google-services-plugin
- https://github.com/firebase/firebase-android-sdk/blob/main/LICENSE
- https://github.com/robolectric/robolectric/releases/tag/robolectric-4.17
- https://github.com/robolectric/robolectric/blob/master/LICENSE
