import AppKit
import SwiftUI
import WebKit

@MainActor
enum MailHTMLWebViewPool {
    private static var idleWebView: MeasuringWebView?

    static func prewarm() {
        guard idleWebView == nil else { return }
        idleWebView = makeWebView()
    }

    static func take() -> MeasuringWebView {
        if let webView = idleWebView {
            idleWebView = nil
            return webView
        }
        return makeWebView()
    }

    static func put(_ webView: MeasuringWebView) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.onWidthChange = nil
        guard idleWebView == nil else { return }
        idleWebView = webView
    }

    private static func makeWebView() -> MeasuringWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        return MeasuringWebView(frame: .zero, configuration: configuration)
    }
}

struct MailHTMLBodyView: View {
    let html: String
    @State private var contentHeight: CGFloat = 44

    var body: some View {
        MailHTMLWebView(html: html, contentHeight: $contentHeight)
            .frame(maxWidth: .infinity, minHeight: 24, idealHeight: contentHeight, maxHeight: contentHeight)
    }
}

private struct MailHTMLWebView: NSViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    func makeNSView(context: Context) -> MeasuringWebView {
        let webView = MailHTMLWebViewPool.take()
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.disableInternalScrollers()
        webView.onWidthChange = { [weak coordinator = context.coordinator, weak webView] in
            guard let webView else { return }
            coordinator?.measure(webView)
        }

        context.coordinator.load(html, in: webView)
        return webView
    }

    static func dismantleNSView(_ webView: MeasuringWebView, coordinator: Coordinator) {
        MailHTMLWebViewPool.put(webView)
    }

    func updateNSView(_ webView: MeasuringWebView, context: Context) {
        context.coordinator.contentHeight = $contentHeight
        context.coordinator.load(html, in: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var contentHeight: Binding<CGFloat>
        private var loadedHTML: String?

        init(contentHeight: Binding<CGFloat>) {
            self.contentHeight = contentHeight
        }

        func load(_ html: String, in webView: WKWebView) {
            guard loadedHTML != html else { return }
            loadedHTML = html
            contentHeight.wrappedValue = 44
            webView.loadHTMLString(Self.document(from: html), baseURL: URL(string: "https://mail.google.com/"))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measure(webView)
            for delay in [0.15, 0.45, 1.2] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    self.measure(webView)
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if navigationAction.navigationType == .linkActivated {
                let scheme = url.scheme?.lowercased() ?? ""
                if ["https", "http", "mailto"].contains(scheme) {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func measure(_ webView: WKWebView) {
            let script = """
                Math.ceil(Math.max(
                    document.body ? document.body.scrollHeight : 0,
                    document.documentElement ? document.documentElement.scrollHeight : 0
                ))
                """
            webView.evaluateJavaScript(script) { [weak self] value, _ in
                guard let self else { return }
                let measured = (value as? NSNumber)?.doubleValue ?? 0
                let height = min(120_000, max(24, ceil(measured)))
                guard abs(self.contentHeight.wrappedValue - height) > 0.5 else { return }
                self.contentHeight.wrappedValue = height
            }
        }

        private static func document(from rawHTML: String) -> String {
            // GmailMessageParser already removes quoted history before the
            // model is persisted. Keep only the security sanitizers here so
            // opening HTML mail does not parse the body twice on the main run loop.
            let sanitized = rawHTML.replacingOccurrences(
                    of: "(?is)<script\\b[^>]*>.*?</script\\s*>",
                    with: "",
                    options: .regularExpression
                )
                .replacingOccurrences(
                    of: "(?is)<meta\\b[^>]*(?:http-equiv|content-security-policy)[^>]*>",
                    with: "",
                    options: .regularExpression
                )
                .replacingOccurrences(
                    of: "(?is)<base\\b[^>]*>",
                    with: "",
                    options: .regularExpression
                )

            return """
                <!doctype html>
                <html>
                <head>
                  <meta charset="utf-8">
                  <meta name="viewport" content="width=device-width, initial-scale=1">
                  <style>
                    :root { color-scheme: light; }
                    html, body {
                      margin: 0 !important;
                      padding: 0 !important;
                      width: 100% !important;
                      min-width: 0 !important;
                      overflow: hidden !important;
                      background: transparent !important;
                    }
                    #mail-content, #mail-content * {
                      box-sizing: border-box !important;
                      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif !important;
                    }
                    #mail-content {
                      color: #292929;
                      font-size: 14px;
                      line-height: 1.5;
                      overflow-wrap: anywhere;
                    }
                    #mail-content > :first-child { margin-top: 0 !important; }
                    #mail-content > :last-child { margin-bottom: 0 !important; }
                    #mail-content img {
                      max-width: 100% !important;
                      height: auto !important;
                    }
                    #mail-content table {
                      max-width: 100% !important;
                    }
                    #mail-content pre {
                      white-space: pre-wrap !important;
                      overflow-wrap: anywhere !important;
                    }
                    #mail-content a, #mail-content a * {
                      color: #292929 !important;
                      text-decoration: underline !important;
                      text-underline-offset: 2px;
                    }
                    #mail-content iframe,
                    #mail-content object,
                    #mail-content embed,
                    #mail-content form,
                    #mail-content input,
                    #mail-content button,
                    #mail-content .gmail_quote,
                    #mail-content .gmail_extra,
                    #mail-content blockquote[type="cite"] {
                      display: none !important;
                    }
                  </style>
                </head>
                <body><div id="mail-content">\(sanitized)</div></body>
                </html>
                """
        }
    }
}

@MainActor
final class MeasuringWebView: WKWebView {
    var onWidthChange: (() -> Void)?
    private var lastMeasuredWidth: CGFloat = -1
    private var didConfigureInternalScrollers = false

    func disableInternalScrollers() {
        guard !didConfigureInternalScrollers else { return }
        let scrollViews = descendantScrollViews(in: self)
        guard !scrollViews.isEmpty else { return }
        for scrollView in scrollViews {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.verticalScrollElasticity = .none
            scrollView.horizontalScrollElasticity = .none
        }
        didConfigureInternalScrollers = true
    }

    override func layout() {
        super.layout()
        disableInternalScrollers()
        guard abs(bounds.width - lastMeasuredWidth) > 0.5 else { return }
        lastMeasuredWidth = bounds.width
        onWidthChange?()
    }

    override func scrollWheel(with event: NSEvent) {
        var ancestor = superview
        while let view = ancestor {
            if let parentScrollView = view as? NSScrollView {
                parentScrollView.scrollWheel(with: event)
                return
            }
            ancestor = view.superview
        }
        super.scrollWheel(with: event)
    }

    private func descendantScrollViews(in view: NSView) -> [NSScrollView] {
        view.subviews.flatMap { child in
            let current = child as? NSScrollView
            return (current.map { [$0] } ?? []) + descendantScrollViews(in: child)
        }
    }
}
