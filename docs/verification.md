# 验证记录

本文件区分代码测试与电话系统端到端验收。没有真实服务器或真机的场景不能标记通过。

## 本地自动化

环境：Flutter 3.47.7 stable / Dart 3.13.5，JDK 17，Android SDK 34/35/36（主工程 target 36）、NDK 28.2、CMake 3.22.1，2026-10-17 至 2026-10-18。

- `flutter pub get`：通过，精确版本与锁文件已生成。
- `dart run build_runner build`：通过，生成 checked DTO。
- `flutter test`：30 项单元/Widget 测试通过。
- `flutter analyze`：通过，无问题。
- `flutter build apk --debug --no-pub`：通过，最新源码重新打包成功。增量压缩缓存曾出现 EOCD 错误，隔离旧生成目录后重新生成并通过产物校验。
- `(cd android && ./gradlew :app:testDebugUnitTest)`：通过，5 项 Robolectric/JUnit 测试，0 失败/错误。覆盖提示有效期、进程存储重建、重复接收、敏感字段不落盘、数量上限及跨实例并发去重。发现并修复 AGP 9 host-test 资源任务对 copyFlutterAssetsDebug 缺失的依赖，保留资源校验。
- `dart run tool/verify_tls.dart`：通过，临时生成本地不可信证书，以实际 HomeLineApi/Dio 发起 HTTPS 握手；证书被拒绝且服务器未收到 HTTP 请求。该测试依赖构建主机 OpenSSL，不保存测试私钥。
- Android 合并 Manifest 检查：通过，原生 HomeMessagingService 存在，FlutterFire 的重复接收/后台服务已移除。
- APK 包检查：ZIP CRC、13 个原生库 ELF 节表范围、apksigner debug 签名校验通过；包名 net.zerexa.homeline、minSdk 26、targetSdk 36。
- 本地 debug APK SHA256：`2787817b4707a2e9a7045714bc5637efef6bd2edda3676df4d0ba2662bcc1627`。不同机器的 debug 密钥/构建环境可能产生不同哈希；此值不是正式发行版签名。
- 首次构建缺少插件所需 SDK 34/35，安装对应平台后构建通过；没有修改插件的编译目标。
- 真机/模拟器集成测试：未运行。

测试覆盖：重复来电去重、只有 SIP CONFIRMED 激活 Telecom、其他设备获胜、claim 途中取消、重复接听点击、会话切换期间的旧响应隔离、终态后的乱序事件、TLS 配置拒绝、不允许 HTTP 重定向、幂等 key 重用、401/403/409、推送过期/不可信状态、号码注入，以及未配置启动 UI、运行时 HTTPS 配置、并行推送恢复去重、实际注册超时、离线会话保留、原生清理失败后退出、回执故障不挂断、HTTP 核验等待期间立即处理 SIP 终态。

## 端到端验收（全部待测试）

| 场景 | 所需环境 | 当前状态 |
|---|---|---|
| 登录并取得服务器个人分机 | 实现契约的 HTTPS 后端 | 未联调 |
| 两台 Android 独立 SIP 注册 | 两台真机、Asterisk WSS/DTLS-SRTP | 未联调 |
| 同时振铃，只有一台获胜 | 原子 claim + PBX fork/CANCEL | 未联调 |
| 锁屏原生 UI 接听/拒接 | Android 26/31/34/36+ 真机 | 原生代码已写，未真机测试 |
| FCM 重复/延迟/休眠唤醒 | Firebase、Google Play 服务、真机 | 原生宿主/恢复代码已写；尚未真机联调 |
| 设备撤销后 PBX 拒绝注册 | 后端和 Asterisk 联动撤销 | 未联调 |
| 多用户外呼串行、不重复拨号 | 后端调度器、FXO 和模拟固话 | 未联调 |
| 扬声器/听筒/蓝牙和音频焦点 | 多版本真机、蓝牙耳机 | 未验证 |
| SIP/网络/服务器重启恢复 | 可故障注入的真实环境 | 代码路径已写，未联调 |
| 无效 TLS 证书连接失败 | 测试证书服务器 | 配置拒绝与本机不可信证书 HTTPS 握手已通过；PBX WSS 真机握手待测试 |
| SRTP 音频双向可听 | PBX + 真机/抓包 | 未验证 |
| Android 集成 smoke test | 模拟器或真机 | 未运行 |
| iOS/Windows/macOS | 各平台 runner 与原生适配 | 尚未实现 |

真实电话验收仍被外部环境阻塞：HomeLine-Server 仓库当前没有 API 实现，本环境没有 Firebase 配置、PBX、FXO 或 Android 真机/可用模拟器。不能把自动化测试中的 fake 适配器称为真实 SIP、FCM 或 Telecom 端到端通过。发布签名支持通过环境变量接入，未提供密钥，未验证签名发行构建。按 deployment.md 准备环境并完成矩阵后才可发布电话功能。

依赖仍使用 Flutter 当前兼容的 legacy Kotlin 插件桥接；firebase_core / flutter_webrtc 尚要求 KGP，编译有上游迁移提示，当前 SDK 构建是否通过以上方最终结果为准。没有通过关闭 TLS、跳过测试或降低编译目标规避错误。
