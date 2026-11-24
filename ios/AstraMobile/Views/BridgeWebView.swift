import SwiftUI
import WebKit

/// 嵌入模式的 WebView：只渲染桌面端手机页的消息流（embed=1）。
/// 安全约束（协议第 7 节）：仅允许导航到绑定桌面的 host:port；
/// 用户点击的其他 http(s) 链接交给系统浏览器打开。
struct BridgeWebView: UIViewRepresentable {
    let url: URL
    let allowedHost: String
    let allowedPort: Int
    /// 变化时强制重载（切换会话/新对话：入口 URL 换 open 参数）
    let reloadToken: Int
    @Binding var activeWebView: WKWebView?

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.lastURL = url
        context.coordinator.lastToken = reloadToken
        webView.load(URLRequest(url: url))
        DispatchQueue.main.async { activeWebView = webView }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.lastToken != reloadToken || coordinator.lastURL != url {
            coordinator.lastURL = url
            coordinator.lastToken = reloadToken
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: BridgeWebView
        var lastURL: URL?
        var lastToken = 0

        init(_ parent: BridgeWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  let host = url.host else {
                decisionHandler(.cancel)
                return
            }
            let port = url.port ?? (url.scheme == "https" ? 443 : 80)
            if host == parent.allowedHost && port == parent.allowedPort {
                decisionHandler(.allow)
            } else if navigationAction.navigationType == .linkActivated,
                      url.scheme == "http" || url.scheme == "https" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}
