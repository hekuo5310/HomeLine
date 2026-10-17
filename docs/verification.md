# 验证记录

本文件区分代码测试与电话系统端到端验收。没有真实服务器或真机的场景不能标记通过。

## 本地自动化

环境：Flutter 3.47.7 stable / Dart 3.13.5，JDK 17，Android SDK 36，2026-10-17。

- `flutter pub get`：通过，精确版本与锁文件已生成。
- `dart run build_runner build`：通过，生成 checked DTO。
- `flutter test`：18 项单元/Widget 测试通过。
- `flutter analyze`：通过，无问题。
- `flutter build apk --debug`：通过，生成 Android debug APK，最终源码增量构建再次通过。Kotlin 原生 Telecom 类已编译入包。
- APK 包检查：ZIP CRC 通过，13 个原生库 ELF 节表范围检查通过；包名 net.zerexa.homeline、minSdk 26、targetSdk 36。
- 真机/模拟器集成测试：未运行。

测试覆盖：重复来电去重、只有 SIP CONFIRMED 激活 Telecom、其他设备获胜、claim 途中取消、重复接听点击、会话切换期间的旧响应隔离、终态后的乱序事件、TLS 配置拒绝、不允许 HTTP 重定向、幂等 key 重用、401/403/409、推送过期/不可信状态、号码注入，以及未配置启动 UI。

## 端到端验收（全部待测试）

| 场景 | 所需环境 | 当前状态 |
|---|---|---|
| 登录并取得服务器个人分机 | 实现契约的 HTTPS 后端 | 未联调 |
| 两台 Android 独立 SIP 注册 | 两台真机、Asterisk WSS/DTLS-SRTP | 未联调 |
| 同时振铃，只有一台获胜 | 原子 claim + PBX fork/CANCEL | 未联调 |
| 锁屏原生 UI 接听/拒接 | Android 26/31/34/36+ 真机 | 原生代码已写，未真机测试 |
| FCM 重复/延迟/休眠唤醒 | Firebase、Google Play 服务、真机 | 无界面恢复未完成 |
| 设备撤销后 PBX 拒绝注册 | 后端和 Asterisk 联动撤销 | 未联调 |
| 多用户外呼串行、不重复拨号 | 后端调度器、FXO 和模拟固话 | 未联调 |
| 扬声器/听筒/蓝牙和音频焦点 | 多版本真机、蓝牙耳机 | 未验证 |
| SIP/网络/服务器重启恢复 | 可故障注入的真实环境 | 代码路径已写，未联调 |
| 无效 TLS 证书连接失败 | 测试证书服务器 | 配置拒绝已测试；实际握手待测试 |
| SRTP 音频双向可听 | PBX + 真机/抓包 | 未验证 |
| Android 集成 smoke test | 模拟器或真机 | 未运行 |
| iOS/Windows/macOS | 各平台 runner 与原生适配 | 尚未实现 |

下一阶段先补齐真实 API/PBX 测试环境，再实现持久原生呼叫宿主、前台服务和后台恢复；完成上述矩阵后才可发布电话功能。Android 不配置发布签名，debug 构建只用于开发验证。
