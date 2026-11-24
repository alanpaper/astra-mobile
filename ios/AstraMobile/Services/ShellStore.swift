import Foundation

/// 壳的中心状态：连接、会话列表、队列、配置、当前会话与 WebView 打开目标。
/// 与页面遵循同一套行为规则（跟进 PC view、新对话发送后收养、运行状态），见协议文档。
@MainActor
final class ShellStore: ObservableObject {
    enum ConnState: Equatable {
        case connecting, connected, disconnected
    }

    enum OpenTarget: Equatable {
        case follow            // 默认态：跟随 PC 正在看的会话（页面自动收养）
        case new               // 新对话（主动新建，不再自动跟进）
        case session(String)   // 指定历史会话
    }

    @Published private(set) var connState: ConnState = .connecting
    @Published private(set) var sessions: [SessionMeta] = []
    @Published private(set) var queue: [QueueItem] = []
    @Published private(set) var config: BridgeConfig?
    @Published private(set) var openTarget: OpenTarget = .follow
    @Published private(set) var scopedSessionId: String?   // scope=one 时锁定
    @Published private(set) var runningSessionIds: Set<String> = []
    @Published private(set) var reloadToken = 0            // 变化触发 WebView 重载
    @Published private(set) var toast: String?
    @Published var senderName: String {
        didSet { UserDefaults.standard.set(senderName, forKey: "senderName.v1") }
    }

    let desktop: BoundDesktop
    private let secret: String
    private var ws: BridgeWebSocket?
    private var msgSeq = 0
    private var backoff: TimeInterval = 1
    private var reconnectTask: Task<Void, Never>?
    private var lastNewSendText: String?
    private var toastResetTask: Task<Void, Never>?

    init(desktop: BoundDesktop, secret: String) {
        self.desktop = desktop
        self.secret = secret
        senderName = UserDefaults.standard.string(forKey: "senderName.v1") ?? "iPhone"
    }

    // MARK: - 派生状态

    var isScoped: Bool { scopedSessionId != nil }
    var isConnected: Bool { connState == .connected }

    /// WebView 顶栏/抽屉用的当前会话标题
    var currentTitle: String {
        switch openTarget {
        case .session(let id):
            return sessions.first { $0.id == id }?.title ?? "会话"
        case .follow, .new:
            if let pc = pcCurrent, let s = sessions.first(where: { $0.id == pc }) {
                return s.title
            }
            return "新对话"
        }
    }

    var isRunningCurrent: Bool {
        let sid: String?
        switch openTarget {
        case .session(let id): sid = id
        case .follow, .new: sid = pcCurrent
        }
        guard let sid else { return false }
        return runningSessionIds.contains(sid)
    }

    private(set) var pcCurrent: String?

    var baseURL: String { "\(desktop.scheme)://\(desktop.host):\(desktop.port)" }

    /// WebView 入口 URL：凭证 + 嵌入模式 + 打开目标（凭证为首段，页面解析兼容旧二维码）
    func entryURL() -> URL? {
        var fragment = "\(secret)&embed=1"
        switch openTarget {
        case .session(let id): fragment += "&open=\(id)"
        case .new: fragment += "&open=new"
        case .follow: break
        }
        return URL(string: "\(baseURL)/m#\(fragment)")
    }

    // MARK: - 生命周期

    func start() {
        connect()
    }

    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        ws?.close()
        ws = nil
    }

    // MARK: - 动作

    /// 打开会话/新对话（WebView 重载，页面走既有 openSession 流程）
    func openSession(_ target: OpenTarget) {
        openTarget = target
        reloadToken += 1
    }

    /// 发送消息进 PC（新对话时 session_id 传 null，PC 自动建会话）
    @discardableResult
    func send(_ text: String) -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        guard isConnected, let ws else {
            showToast("未连接到 PC，请稍候重试")
            return false
        }
        msgSeq += 1
        var command: [String: Any] = [
            "type": "send",
            "msg_id": msgSeq,
            "text": body,
            "sender": senderName,
        ]
        switch openTarget {
        case .session(let id): command["session_id"] = id
        case .follow, .new: command["session_id"] = NSNull()
        }
        if case .new = openTarget { lastNewSendText = body }
        sendCommand(command)
        return true
    }

    func queueReorder(item: QueueItem, target: QueueItem, after: Bool) {
        sendCommand(["type": "queue_reorder", "id": item.id,
                     "target_id": target.id, "after": after])
    }

    func queueRemove(item: QueueItem) {
        sendCommand(["type": "queue_remove", "id": item.id])
    }

    func setThinking(enabled: Bool) {
        let effort = config?.thinkingEffort ?? "medium"
        sendCommand(["type": "set_thinking", "enabled": enabled, "effort": effort])
    }

    func setThinkingEffort(_ effort: String) {
        sendCommand(["type": "set_thinking", "enabled": true, "effort": effort])
    }

    func setModelPort(_ port: Int) {
        sendCommand(["type": "set_model", "source": "model", "port": port])
    }

    func setModelProvider(_ providerId: String) {
        sendCommand(["type": "set_model", "source": "provider", "provider_id": providerId])
    }

    func setOverrideModel(_ model: String) {
        guard let pid = config?.providerId else { return }
        sendCommand(["type": "set_model", "source": "provider", "provider_id": pid, "model": model])
    }

    func setAutoMode(_ mode: String) {
        sendCommand(["type": "set_auto_mode", "mode": mode])
    }

    func refreshSessions() {
        Task {
            if let list = try? await BridgeAPI.sessions(base: baseURL, secret: secret) {
                sessions = list
            }
        }
    }

    // MARK: - 连接管理

    private func connect() {
        connState = .connecting
        Task {
            do {
                let ticket = try await BridgeAPI.ticket(base: baseURL, secret: secret)
                ws?.close()  // 换新连接前先收掉旧的
                let socket = BridgeWebSocket(scheme: desktop.scheme, host: desktop.host, port: desktop.port)
                socket.onEvent = { [weak self] event in self?.handleEvent(event) }
                socket.onStateChange = { [weak self] open in
                    if !open { self?.handleDisconnected() }
                }
                ws = socket
                socket.connect(ticket: ticket)
            } catch {
                showToast("连接失败：\(error.localizedDescription)")
                scheduleReconnect()
            }
        }
    }

    private func handleDisconnected() {
        guard connState != .disconnected else { return }
        connState = .disconnected
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        let delay = backoff
        backoff = min(backoff * 2, 10)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    private func sendCommand(_ command: [String: Any]) {
        guard isConnected, let ws else {
            showToast("未连接到 PC，请稍候重试")
            return
        }
        ws.send(json: command) { [weak self] ok in
            DispatchQueue.main.async {
                if !ok { self?.showToast("发送失败，请稍候重试") }
            }
        }
    }

    private func showToast(_ text: String) {
        toast = text
        toastResetTask?.cancel()
        toastResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: - 事件处理（与页面 handleServer/trackRunning 同一套规则）

    private func handleEvent(_ event: ShellEvent) {
        switch event {
        case .hello(let sessions, let queue, let config, let current, let scope):
            self.sessions = sessions
            self.queue = queue
            self.config = config
            pcCurrent = current
            scopedSessionId = scope == "one" ? current : nil
            connState = .connected
            backoff = 1
        case .view(let sid):
            // 与页面同一规则：仅停在默认态（follow）时页面会自动收养并渲染，
            // 壳只记录用于标题展示，不重载 WebView（避免双重加载）
            pcCurrent = sid
        case .queue(let items):
            queue = items
        case .config(let config):
            self.config = config
        case .toast(let text):
            showToast(text)
        case .runSettled(let sid):
            if let sid { runningSessionIds.remove(sid) }
            refreshSessions()  // 新会话首次落盘后让列表出现
        case .envelope(let env):
            handleEnvelope(env)
        }
    }

    private func handleEnvelope(_ env: [String: Any]) {
        let sid = env["session_id"] as? String
        switch env["type"] as? String {
        case "message_delta", "thinking_delta", "tool_call_started",
             "tool_call_args_delta", "permission_requested", "status_changed":
            if let sid { runningSessionIds.insert(sid) }
        case "run_completed", "run_failed", "run_cancelled":
            if let sid { runningSessionIds.remove(sid) }
        case "user_message":
            // 新对话发送后的收养：PC 广播的 user_message 与本机最近一次发送文本匹配
            if case .new = openTarget, let sid,
               let text = env["text"] as? String,
               text == lastNewSendText {
                lastNewSendText = nil
                openSession(.session(sid))
            }
        default:
            break
        }
    }
}
