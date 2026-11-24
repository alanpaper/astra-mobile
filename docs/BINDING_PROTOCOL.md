# Astra 桌面绑定协议（v1）

Astra 手机客户端（壳）与桌面端「手机遥控桥」之间的契约。壳不解析对话业务，
只负责三件事：扫码/深链 → 保管凭证 → 加载桌面端提供的手机页。

## 1. 绑定载荷

二维码内容是一个入口 URL：

```
http(s)://<host>:<port>/m#<SECRET>
```

- **局域网模式**：`host` = 桌面端局域网 IP，`port` = 桥端口
- **中继模式**：`host:port` = 中继服务器的数据端口（桌面端经 relay 转发，可跨公网）
- `SECRET` 两类：
  - **临时 token**：只存在于二维码与桌面端内存，桌面端重启即失效
  - **持久设备 key**：`mbk_` + 64 位 hex；桌面端只存 SHA-256 指纹，
    支持设置失效时间与随时撤销（撤销立即踢掉在线连接）
- 壳的解析规则：scheme ∈ {http, https}，路径为 `/m`，fragment 非空；
  以 `host:port` 作为一台桌面的唯一标识，凭证按此维度隔离存储

## 2. 凭证生命周期（页面约定）

- 手机页（`/m`）打开后把 fragment 中的 secret 一次性读入，
  存入 sessionStorage/localStorage（`mbk_` 前缀），随后清理地址栏
- 壳重新加载入口页时**始终带上 `#<secret>`**（从系统安全存储读取），
  页面会自行刷新凭证 —— 壳无需了解页面内部存储格式
- **嵌入模式**（原生壳）：fragment 可附加参数（首段仍为 secret，旧二维码兼容）：
  - `embed=1`：页面隐藏自带顶栏/输入区/抽屉/队列/配置，只渲染消息流，
    这些 chrome 由壳原生提供
  - `open=<sessionId|new>`：首连 hello 时打开指定会话（或进入新对话模式），
    优先生效且阻止对 PC current 的自动收养

## 3. HTTP API（认证：`Authorization: Bearer <SECRET>`）

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/ticket` | 换一次性短时效票据，响应 `{ticket, scope, session_id}` |
| GET | `/api/sessions` | 会话元数据列表（按更新时间倒序） |
| GET | `/api/session/:id` | 单会话详情 |

- 票据仅用于 WS 连接（query `?ticket=`），避免长期凭证进 URL（会进日志）
- 认证失败按客户端 IP 指数退避封禁（持久 key 无法被暴力枚举）

## 4. WebSocket

- `GET /api/ws?ticket=<一次性票据>`
- 桌面端把 Agent 运行事件镜像推给**所有**连接（页面与壳各持一条互不冲突）
- 事件（壳与页面共用）：`hello`（sessions/queue/config/current/scope）、
  `view`、`queue`、`config`、`toast`、`run-settled`、`agent-event` 等
- 命令：`send`（session_id 为 null 即发进新对话）、`queue_reorder`、
  `queue_remove`、`set_model`、`set_thinking`、`set_auto_mode`、
  审批/提问处置 —— 壳的输入条/队列/配置面板全部复用这些命令，协议层零新增
- 页面行为规则（壳保持一致）：PC 切换会话仅收养停在默认态的设备；
  新对话发送后按广播的 user_message 文本匹配收养新会话

## 4.1 形态分工（嵌入模式）

| 层 | 负责 |
|---|---|
| WebView 内页面 | 仅消息流渲染（markdown/工具卡/提问/审批弹卡） |
| 壳原生 | 顶栏（标题/队列角标/新对话）、左抽屉（搜索+历史+用户入口）、输入条、队列面板、配置面板（思考/模型/放权/本机名称） |

## 5. Scope（服务端强制）

- `all`：全部会话；`session:<id>`：仅绑定的单会话
- 过滤在桌面端桥层执行（hello 快照 / HTTP / 事件转发 / WS 命令），
  客户端 UI 只负责展示，不承担安全职责

## 6. 失效与撤销

- 桌面端撤销 key → 立即踢掉该设备的在线连接
- 凭证过期/被撤销时，页面展示 401 门页；
  壳提供「重新扫码 / 切换桌面」入口

## 7. 安全边界（壳的义务）

- secret 只存系统安全存储（iOS Keychain / 后续 Android Keystore）
- 不写日志、不进剪贴板历史、不在 UI 明文展示
- WebView 限制导航只允许绑定桌面的 `host:port`，外链交给系统浏览器
- 明文 http 的风险：局域网内可见；公网部署请给中继加 TLS 终止
  （stunnel / nginx stream / Caddy l4）

## 8. 版本

- 协议版本 v1
- 页面与协议随桌面端自升级，壳只加载桌面端提供的 `/m` 页面，
  因此壳与桌面端之间**不需要版本握手**
- 深链：`astra://bind?url=<URL 编码后的入口 URL>`
