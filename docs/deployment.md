# 部署与真机验收

本项目交付客户端及契约提案。HomeLine-Server 当前仅有 README/LICENSE，尚无可联调 API；以下服务器条件必须由运营者实现，不能通过填写一个 URL 自动补齐。

## 服务器准备

1. 实现 api-contract.md 的 HTTPS API、设备作用域会话、每设备 SIP 凭据、原子 claim、服务端事件及外呼幂等调度。访问令牌过期要求重新认证；撤销设备必须同时移除 PBX contact、认证资格与 FCM 绑定。
2. 配置有效域名证书的 WSS SIP、WebRTC DTLS-SRTP、ICE/rtcp-mux，按网络需要设置受控 TURN。当前客户端不支持裸 5061 SIP TLS；不要关闭证书检查。
3. 每设备独立 endpoint/auth/AOR，个人分机聚合各设备；给每个设备 leg 维护实际 SIP Call-ID 到业务 call_id 的映射。PBX 等待恢复/注册后再投递 INVITE，claim 获胜后 CANCEL 其他设备。
4. 外线仅由服务器调度器使用 FXO。单模拟线路同一时刻只有一通外线；任务幂等表与线路租约需事务性维护。普通设备 SIP 拨号计划不能绕过排队。
5. Firebase 服务账号只保留服务器侧。发送 high-priority data-only 消息，设置与 expires_at 一致的短 TTL（客户端最大接受 120 秒）；不要携带 notification、密码或用户令牌。区分 FCM accepted 与 App received/restored/registered/ringing/connected，超时进入备用路由。

示例 FCM HTTP v1 `message`（服务器根据自己的项目与令牌发送）：

```json
{"token":"device-fcm-registration-token","android":{"priority":"high","ttl":"30s"},"data":{"type":"incoming_call","call_id":"server-call-id","expires_at":"2026-10-17T18:00:30Z"}}
```

## Android 配置与安装

- Flutter 3.47.7、Dart 3.13.5、JDK 17、Android SDK 36；支持 Android API 26+。
- 在 Firebase 为包名 `net.zerexa.homeline` 创建 Android app，将下载配置放入 `android/app/google-services.json`。该文件被 Git 忽略；构建自动应用 Google Services 插件。没有配置时 FCM 保持关闭。
- `flutter pub get --enforce-lockfile` 后运行：

```sh
flutter build apk --debug --dart-define=ENABLE_FCM=true
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

首次打开填写 HTTPS API 地址并登录；地址保存在安全存储。也可以添加 `--dart-define=API_BASE_URL=https://phone-api.example.org` 固定部署地址。首次在前台授予麦克风和通知权限，在设置启用系统通话；Android 14+ 按页面引导允许全屏来电。后台不会弹出麦克风权限申请。设置页可查询 API 延迟、实际注册状态、通知/全屏权限和恢复阶段。

来电时使用原生 ConnectionService、CallStyle 通知和锁屏 Activity；Flutter 页面与原生 Activity 复用同一引擎。电话前台服务只在呼叫/有效恢复过程中工作，不从开机广播常驻。Android 降级 FCM 或拒绝后台启动时保留未过期提示，等待用户打开；不会违规启动界面。

用户强制停止、无 Google Play 服务、设备离线、厂商后台限制时，来电可能无法及时送达。运营者必须配置 PBX 超时和备用路由，不能承诺推送必达。测试不应通过关闭 Android 安全限制掩盖问题。

## 发布签名

通过自己的秘密管理工具向构建进程注入以下环境变量：
`HOMELINE_KEYSTORE`（绝对路径）、`HOMELINE_STORE_PASSWORD`、`HOMELINE_KEY_ALIAS`、`HOMELINE_KEY_PASSWORD`。
不要把 keystore 或密码提交到仓库，也不要在日志打印变量。

```sh
flutter build appbundle --release --dart-define=ENABLE_FCM=true
```

未提供签名时不会改用 debug 密钥；生成的未签名产物不能作为正式安装发行包。发布前在提供正确签名的环境运行 release 构建、Android 签名校验、16 KB 页面兼容和下列真机矩阵。当前只验证 debug 构建，不声称已完成商店发布。

## 实机矩阵

至少两台安装 Google 服务的 Android，覆盖 API 26、31、34、36，另准备蓝牙耳机和可抓包 PBX。每轮记录 OS/厂商/网络、业务 call_id、每设备 leg ID、服务端阶段时间、SIP/PBX 状态与实际音频；禁止记录认证内容。

- 同账号两设备登录、不同认证、同时振铃、先接听者获胜；另一端无残留 UI/声音；claim 等待中拒接仍立即停止。
- 锁屏、切后台、系统回收进程后推送；核实复用/新建唯一引擎，REGISTER 后才投递 INVITE；通话继续时 Activity 销毁不销毁媒体。
- 重复、乱序、过期推送，断网、FCM 降级、用户强停；无重复 Telecom call、无假接通，PBX 按期限进入备用路由。
- 账号禁用、设备撤销、会话过期、凭据轮换；失效设备无法新注册/接听/外呼，活跃通话按服务器策略结束。
- 扬声器、听筒、蓝牙、另一应用抢占 Telecom 焦点；音频双向、焦点正确释放、挂断清理前台服务。
- 无效 TLS/WSS 证书、网络切换、服务器重启；无不安全降级，恢复后可重新呼叫；进程死亡不会把旧媒体显示为 active。
- 多用户 FXO 排队、重复提交/重启重试、取消等待任务、忙线与失败提示；从 PBX/网关记录证明没有重复拨号或并行抢线。

通过这些项目后再将 verification.md 的对应行标记为通过。当前不具备这些测试资源，不把 JVM/Widget 测试结果代替电话验收。
