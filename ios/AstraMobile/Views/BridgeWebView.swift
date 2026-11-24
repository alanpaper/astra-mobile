import SwiftUI
import WebKit

/// 全屏加载桌面端手机页的 WebView。
/// 安全约束（协议第 7 节）：仅允许导航到绑定桌面的 host:port；
/// 用户点击的其他 http(s) 链接交给系统浏览器打开。
struct BridgeWebView: UIViewRepresentable {
    let url: URL
    let allowedHost: String
    let allowedPort: Int
    @Binding var activeWebView: WKWebView?

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        DispatchQueue.main.async { activeWebView = webView }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastLoaded != url {
            context.coordinator.lastLoaded = url
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: BridgeWebView
        var lastLoaded: URL?

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
