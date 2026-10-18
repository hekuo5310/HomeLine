# HomeLine API v1 — 待实现的契约提案

**仓库没有服务器。本文件不代表现有服务器 API，未完成真实联调。**
客户端 `HomeLineApi` 实现此契约；上线前服务器负责人必须确认并实现它。协议错误应拒绝操作，不回退至模拟通话。

所有端点使用 HTTPS；禁止将 bearer 放进 URL、禁止跨域重定向。登录以外请求必须带 `Authorization: Bearer <device-scoped-session-token>`。服务器从会话推导 user_id/device_id，不信任客户端 UUID 或请求体中的所有者字段。请求/响应 Content-Type 为 application/json。时间均为 RFC3339 UTC；ID 为不透明字符串。未知字段可忽略；必填字段缺失或类型错误拒绝解析。

## 会话与设备

| 方法与路径 | 请求 | 成功响应 |
|---|---|---|
| POST /v1/sessions | `{username,password,device_name,platform:"android"}` | Session，201 |
| GET /v1/session | 无 | Session，200；检查账号、设备和会话有效性 |
| DELETE /v1/session | 无 | `{}`，200；撤销会话并撤销设备 SIP 授权和推送绑定 |
| GET /v1/snapshot | 无 | Snapshot，200 |
| PATCH /v1/devices/{id} | `{name}` | `{}`，200；只能重命名自己的设备 |
| DELETE /v1/devices/{id} | 无；Idempotency-Key | `{}`，200；重复撤销返回相同结果 |
| PUT /v1/devices/current/push-token | `{provider:"fcm",token:string或null}` | `{}`，200；null 表示解绑 |
| POST /v1/devices/current/sip-credentials | 无 | SipCredentials，200，Cache-Control: no-store |

Session：
```json
{"access_token":"opaque-device-session","expires_at":"2026-10-18T14:00:00Z","user_id":"u1","extension":"1001","device_id":"server-issued-device-id","account_status":"active","device_limit":null}
```

`device_limit: null` 表示服务器没有下发固定数量；客户端不得擅自设限。登录必须限速和验证密码，由服务器事务性执行设备配额策略。当前 MVP 不使用 refresh token，会话过期要求重新认证。`GET /session` 应返回同一设备的新有效 access_token 或仍有效的原令牌。

Device：`{id,name,status:"active"|"revoked",last_seen_at}`。禁用账号/设备后，服务器必须同时拒绝 REST、事件订阅、凭据下发、SIP REGISTER/INVITE 和接听仲裁；立即从 PBX 清除 contact/认证资格，按策略终止现有呼叫。客户端轮询不构成服务器安全边界。

SipCredentials：
```json
{"web_socket_url":"wss://pbx.example.org/ws","uri":"sip:device-a@pbx.example.org","authorization_user":"device-a","password":"short-lived-per-device-secret","expires_at":"2026-10-17T15:00:00Z","ice_servers":[{"urls":"turns:turn.example.org:5349","username":"short-lived-user","credential":"short-lived-secret"}]}
```

每设备独立 endpoint/auth/AOR；逻辑分机只用于服务器聚合设备。凭据不落普通配置、不写日志；此 MVP 只保存在内存。SIP SDK 使用 WSS 而不是裸 5061 TLS。Asterisk WebRTC endpoint 需启用 DTLS-SRTP、ICE、rtcp_mux 和有效 WSS 证书。客户端没有 TLS 降级开关。服务器不得把 AMI/ARI 或管理员密钥下发给客户端。ICE 列表必须明确返回；客户端不擅自使用第三方 STUN。

## Snapshot 与呼叫

```json
{"account_status":"active","device_status":"active","line_status":"idle","can_call":true,"devices":[],"calls":[],"outbound_tasks":[],"history":[]}
```

`line_status` 由交换机返回，如 idle/busy/offline。`can_call` 是服务器权限策略，不能只由客户端推断。Snapshot 每 5 秒轮询，30 秒不能成功验证设备权限就停止 SIP；WebSocket 事件仅触发提前刷新。服务器应限制集合数量并保留最近的终态直到设备完成同步；不能无声丢弃当前设备尚未观察到的终态。

Call：
```json
{"id":"business-call-id","sip_call_id":"wire-call-id-for-current-device-leg","state":"ringing","remote":"13800138000","updated_at":"2026-10-17T14:00:00Z","revision":3,"answered_device_id":null,"queue_position":null,"waiting_since":null}
```

`id` 是逻辑呼叫 ID，`sip_call_id` 是当前设备 SIP leg 的原始 Call-ID，**不是** sip_ua helper 加了 from-tag 的复合 ID，也不能假定所有设备或 PBX 两侧使用同一个 SIP Call-ID。服务器维护各 leg 到业务呼叫的映射。`revision` 对业务呼叫严格递增。同一呼叫重新排队/重拨产生新业务 ID 和新 SIP leg，不能复用已终止 ID。

状态：waiting、ringing、claimed、connected、ended、failed、cancelled、timeout。connected 只有交换机确认后可返回；HTTP 接听请求不能自行生成该状态。queue_position/waiting_since 只在服务器确实知道时返回。

| 方法与路径 | 请求 | 成功响应 |
|---|---|---|
| GET /v1/calls/{id} | 无 | 当前用户和设备可见的 Call，200；不存在/不可见为 404 |
| POST /v1/calls/{id}/device-events | `{stage}` + Idempotency-Key | `{}`，200；由服务器分配接收时间 |
| POST /v1/calls/resolve | `{sip_call_id}` | 当前设备有权限的 Call，200 |
| POST /v1/calls/{id}/claim | Idempotency-Key | Call，200，包含 answered_device_id |
| POST /v1/calls/{id}/reject | Idempotency-Key | Call，200；只拒绝当前设备 leg，其他设备是否继续由服务器策略决定 |
| POST /v1/calls/{id}/hangup | Idempotency-Key | Call，200 |

claim 必须事务性比较并写入接听者。只有 ringing 且无人获得接听权时才授予当前设备；同设备重试返回原结果，其他设备返回 409。授予后让获胜设备的 INVITE 保持可应答，并向其他 leg 发送 CANCEL；不能在 claim 时向外线伪造已接通。设置短期 claim 超时，SIP 未完成要释放/结束呼叫，防止网络错误永久占用队列。服务端事件与 SIP CANCEL 都用于收敛其他设备界面。

SIP 引擎收到 CONFIRMED 才驱动客户端和 Telecom active；DTLS-SRTP 音频质量仍需真实设备验收。客户端拒接和挂断优先终止本机 SIP，然后尽力提交服务端确认；PBX 必须以真实信令为准。

## 外呼排队

| 方法与路径 | 请求 | 成功响应 |
|---|---|---|
| POST /v1/outbound-tasks | `{destination}` + Idempotency-Key | QueueTask，201；同一 key 重试返回同一个任务 |
| POST /v1/outbound-tasks/{id}/cancel | Idempotency-Key | `{}`，200；只允许 waiting；状态变更冲突返回 409 |

QueueTask：
```json
{"id":"task1","destination":"13800138000","state":"waiting","revision":1,"position":2,"estimated_wait_seconds":null,"failure_reason":null}
```

状态：waiting → dialing → ringing → connected → completed，或 failed/cancelled。失败必须返回 failure_reason；position、estimated_wait_seconds 不可靠时返回 null。任务位置、优先级及 FXO 线路占用由服务器控制。客户端仅个人分机允许 SIP 直拨；服务器拨号计划还必须拒绝设备通过 SIP 绕过外呼队列。

幂等表以 `(user_id,device_id,operation,key)` 唯一，保存请求摘要和结果。相同 key + 不同请求体返回 409。先提交任务事务，再由调度器以原子线路租约串行执行。不能在 API 网络重试时重复对 FXO 发起拨号。幂等记录保留应至少覆盖客户端所有未确认请求（建议保留任务生命周期加 30 天）；客户端在 SQLite 保存未确认号码与 key，重启后复用。此 MVP 未确认任务需先重试确认，才允许提交不同号码。

## 事件与推送

`GET /v1/events` 升级为 WebSocket，使用 Authorization header，TLS。只发送当前会话可见的状态失效通知，例如 `{type:"snapshot_changed"}`；不得包含凭据。客户端重连后先全量 Snapshot。事件只用于加快同步，5 秒轮询是当前的兜底路径。服务端应对连接与消息频率限速，撤销设备后断开连接。

FCM data 消息：`{type:"incoming_call",call_id:"business-id",expires_at:"RFC3339"}`，高优先级、短 TTL，不放 SIP 密码或会话令牌。服务端分别记录发送已受理、客户端收到、恢复、REGISTER 成功、振铃、接通，不能合并为一个 delivered 状态。Android 原生接收器消费 data-only 提示；系统降级为普通优先级时只保存提示、不违规启动后台服务。服务端必须依据真实回执判断是否需要备用路由。

`device-events.stage` 允许 received、restored、registered、ringing、connected、failed、media_lost。幂等 key 按设备/业务呼叫/阶段稳定生成，请求体仅包含 stage，服务器记录接收时间，允许迟到和乱序但不能倒退权威呼叫状态。FCM accepted 由发送服务记录，不由 App 声明。restored 表示安全会话及呼叫查询成功，registered 必须等到 SIP SDK 实际 REGISTER 成功；ringing 在真实 SIP INVITE 且 Telecom show 成功后上报；connected 仅由 SIP CONFIRMED 触发。服务器仍以 PBX 事件确认实际线路状态，不应把客户端回执当作授权或计费依据。

PBX 唤醒策略：外部来电先由交换机保留（例如等待路由/队列），服务端推送后等指定设备 registered 回执，再向其当前有效 contact 投递 INVITE。注册期间不要让所有 fork leg 提前 480 导致外线结束。各设备必须使用不同 Call-ID leg，原子 claim 获胜后取消其他 leg。回执/注册/接听各有独立超时，超过有效期进入无人接听、语音信箱或运营者指定备用路由；FCM 成功受理不代表来电成功。

media_lost 表示引擎进程重建时发现历史活跃 ID，后端应核查该设备 leg、结束已丢失的媒体、释放线路租约并更新记录。客户端不从本地 ID 恢复 active。服务器在推送令牌 UNREGISTERED/INVALID_ARGUMENT（确认不是 payload 错误）时撤销对应绑定；客户端下次启动/刷新令牌重新绑定。

## 错误与授权

401：过期会话；403：禁用/撤销/无权限；404：资源不可见；409：状态竞争或幂等冲突；429：限速；5xx：服务不可用。响应可为 `{code:"stable_error_code",message:"safe_message"}`，当前客户端使用本地安全文案而不展示敏感服务器原文。服务器必须逐项验证所有者，不以 ID 难猜为权限校验。TLS 错误绝不能重试 HTTP/WS。
