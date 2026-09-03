import AppKit
@preconcurrency import WebKit

/// WKWebView 인스턴스와 EditorBridge의 생명주기를 소유한다.
/// 외부 네트워크 로딩은 CSP(index.html)로 막아두었고, 여기서는 로컬 file:// 로드가 아닌
/// 모든 내비게이션(링크 클릭 등)을 취소하고 기본 브라우저로 위임하는 2차 방어선을 둔다.
@MainActor
final class RichEditorController: NSObject {
    let webView: WKWebView
    let bridge = EditorBridge()

    var delegate: EditorBridgeDelegate? {
        get { bridge.delegate }
        set { bridge.delegate = newValue }
    }

    override init() {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        configuration.userContentController = contentController
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        // 문서 상태는 전부 Swift/SQLite가 갖고 있고 WKWebView는 순수 렌더링 엔진일 뿐이라
        // 쿠키·localStorage·디스크 캐시를 프로세스 사이에 보존할 이유가 없다. 기본(영구)
        // 데이터 스토어를 쓰면 file:// 하위 리소스(editor.bundle.js 등)가 WebKit의 디스크
        // 네트워크 캐시에 남아서, 앱을 재설치해 같은 경로에 새 파일을 깔아도 이전 빌드의
        // 스크립트가 그대로 로드되는 경우가 있었다 — 매 실행마다 새 임시 스토어를 쓰면
        // 원천적으로 재발하지 않는다.
        configuration.websiteDataStore = .nonPersistent()

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        contentController.add(bridge, name: EditorBridge.messageHandlerName)
        bridge.webView = webView
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false

        #if DEBUG
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        #endif

        loadEditorHTML()
    }

    private func loadEditorHTML() {
        guard let indexURL = WebEditorResources.indexHTMLURL,
              let directoryURL = WebEditorResources.webEditorDirectoryURL else {
            delegate?.editorBridge(bridge, didReportError: "WebEditor 리소스를 찾을 수 없습니다 (앱 번들 손상 가능성).")
            return
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: directoryURL)
    }

    func loadDocument(_ document: EditorDocument) {
        bridge.loadDocument(document)
    }

    func applyCommand(_ name: String, args: [String: Any]? = nil) {
        bridge.applyCommand(name, args: args)
    }

    func setTheme(isDark: Bool) {
        bridge.setTheme(isDark: isDark)
    }

    func setEditable(_ isEditable: Bool) {
        bridge.setEditable(isEditable)
    }

    func focusEditor() {
        bridge.focusEditor()
    }

    /// 분할 편집에서 패널마다 독립적인 확대 비율을 갖기 위해 WKWebView 자체의 pageZoom을 쓴다
    /// (스펙 9절 "각 편집기는... 확대 비율... 독립적으로 가진다").
    func setZoom(_ factor: Double) {
        webView.pageZoom = factor
    }

    /// 패널별 독립 찾기 상태 (스펙 9절 "검색 상태"). WKWebView의 네이티브 하이라이트를 그대로 쓴다.
    func find(_ text: String, backwards: Bool = false, completion: @escaping (Bool) -> Void = { _ in }) {
        guard !text.isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(text, configuration: configuration) { result in
            completion(result.matchFound)
        }
    }
}

extension RichEditorController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        if navigationAction.navigationType == .other, url?.isFileURL == true {
            decisionHandler(.allow)
            return
        }
        if let url {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }
}
