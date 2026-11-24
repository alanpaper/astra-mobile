import Foundation

/// 扫码/深链解析出的绑定目标。
/// 载荷：http(s)://<host>:<port>/m#<SECRET>（见 docs/BINDING_PROTOCOL.md）
struct BindTarget: Equatable {
    let scheme: String
    let host: String
    let port: Int
    let secret: String

    /// 一台桌面端的唯一标识，凭证按此维度隔离
    var identifier: String { "\(host):\(port)" }

    static func parse(_ raw: String) -> BindTarget? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed) else { return nil }
        guard comps.scheme == "http" || comps.scheme == "https" else { return nil }
        guard let host = comps.host, !host.isEmpty, let port = comps.port else { return nil }
        let path = comps.path
        guard path == "/m" || path == "/m/" || path.isEmpty || path == "/" else { return nil }
        guard let secret = comps.fragment?.trimmingCharacters(in: .whitespaces),
              !secret.isEmpty else { return nil }
        return BindTarget(scheme: comps.scheme!, host: host, port: port, secret: secret)
    }
}

/// 已绑定的桌面端（元数据持久化在 UserDefaults；secret 在 Keychain）
struct BoundDesktop: Codable, Identifiable, Equatable {
    let scheme: String
    let host: String
    let port: Int
    let addedAt: Date
    var updatedAt: Date

    var id: String { "\(host):\(port)" }
    var label: String { "\(host):\(port)" }
}
