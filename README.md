# HomeLine

Flutter + Dart 自建家庭电话客户端。**当前为可构建、待服务端与真机联调的客户端工程。** 保留 MPL-2.0 许可证。

已有：分层客户端、Material 3 页面、Riverpod、GoRouter、Dio 与生成式 DTO、HTTPS 检查、Keystore/Keychain 安全会话、独立设备列表/撤销、SIP WSS/WebRTC 适配、Android Telecom 原生桥接、服务端接听仲裁、SQLite 外呼幂等重试、队列/历史显示、WebSocket 提示与轮询恢复、自动化测试和 Android 构建流程。

**后端 API 是待实现契约，不是已存在的服务。** Android 已实现应用级通话引擎、phoneCall 前台服务、原生 FCM 唤醒提示持久化、会话恢复、实际 REGISTER 等待、服务端呼叫核验和 Telecom 来电链路。代码及测试不等于双设备、锁屏、真实音频或 FXO 已验收；完整状态见 [验收记录](docs/verification.md)。应用不会生成假的注册成功、来电或接通状态。

## 构建

使用 Flutter **3.47.7 stable / Dart 3.13.5**、JDK 17、Android SDK（Flutter 指定的 compile/target SDK）、minSdk 26。依赖精确版本与传递依赖锁文件入库。

```sh
flutter pub get --enforce-lockfile
dart run build_runner build
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter build apk --debug
(cd android && ./gradlew :app:testDebugUnitTest)
```

APK：`build/app/outputs/flutter-apk/app-debug.apk`。首次启动可输入并安全保存 HTTPS 服务器地址；也可在构建时指定：

```sh
flutter run --dart-define=API_BASE_URL=https://your-phone-api.example.org
```

服务器必须实现 [API 契约提案](docs/api-contract.md)。不得用 Asterisk AMI/ARI URL 代替客户端 API。先在“设置”启用 Android 系统通话集成，允许麦克风/通知；Android 14+ 按提示允许全屏来电通知。OEM/系统版本行为需真机检查。内部个人分机通过 SIP，外线号码提交服务器队列。

SIP 选用 `sip_ua` 1.1.0：**SIP over WSS（TLS）+ WebRTC DTLS-SRTP**，没有实现裸 SIP TLS 5061。需要 Asterisk 配置 WebRTC、有效 WSS 证书、DTLS-SRTP/ICE/TURN。媒体加密与音频接通仍需服务器/真机抓包与通话验证。

FCM 默认关闭。运营者将自己 Firebase Android 项目的 `google-services.json` 放在 `android/app/`（已忽略），构建脚本会自动应用 Google Services 插件，然后使用 `--dart-define=ENABLE_FCM=true`。服务端发送 high-priority data-only 来电提示；不要使用 notification 消息代替它。禁止向 App 放入 Firebase 服务账号私钥或发送密钥。详见 [部署与真机验收](docs/deployment.md)。

集成 smoke test 需要 Android 模拟器/真机（不带 API_BASE_URL）：

```sh
flutter test integration_test/setup_test.dart -d <android-device-id>
```

发布者需提供自己的正式签名；本仓库不使用 debug 密钥签署 release。GitHub Actions 验证分析、测试和 debug APK，并上传构建产物。

## 说明

- [架构与未完成项](docs/architecture.md)
- [API 契约](docs/api-contract.md)
- [依赖、许可证与平台](docs/dependencies.md)
- [验收记录](docs/verification.md)

当前没有内置体验账号、管理员密钥或模拟 SIP 连接。没有设备、PBX、后端和 Firebase 项目时，不能验证两个手机接听、锁屏来电、真实音频或 FXO 队列。后续必须按验收记录完成这些测试，才能将本工程称为可用电话客户端。
