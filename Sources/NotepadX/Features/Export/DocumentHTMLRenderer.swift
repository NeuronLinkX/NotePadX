import Foundation
@preconcurrency import WebKit

/// 내보내기용 HTML 조각을 만들 때, 자체 HTML 렌더러를 새로 짜는 대신 실제 편집기가 쓰는
/// Tiptap 렌더러를 오프스크린 WKWebView로 한 번 더 띄워서 그 결과 DOM을 그대로 가져온다.
/// 이렇게 하면 코드 구문 강조, 표, 체크리스트 등이 화면에 보이는 것과 정확히 같은 모습으로 나온다.
@MainActor
final class DocumentHTMLRenderer: NSObject, EditorBridgeDelegate {
    private let controller = RichEditorController()
    private var readyContinuation: CheckedContinuation<Void, Never>?
    private var isReady = false

    override init() {
        super.init()
        controller.delegate = self
        controller.setEditable(false)
    }

    /// `<div id="editor-root">` 내부의 렌더링된 HTML 조각(ProseMirror 결과물)을 돌려준다.
    func renderBodyHTML(document: EditorDocument, isDark: Bool) async -> String {
        if !isReady {
            await withCheckedContinuation { continuation in
                self.readyContinuation = continuation
            }
        }
        controller.setTheme(isDark: isDark)
        controller.loadDocument(document)
        let result = try? await controller.webView.evaluateJavaScript(
            "document.getElementById('editor-root').innerHTML"
        )
        return (result as? String) ?? ""
    }

    func editorBridgeDidBecomeReady(_ bridge: EditorBridge) {
        isReady = true
        readyContinuation?.resume()
        readyContinuation = nil
    }

    func editorBridge(_ bridge: EditorBridge, didChangeDocument document: EditorDocument, plainText: String) {}
    func editorBridge(_ bridge: EditorBridge, didChangeHeadings headings: [HeadingOutlineItem]) {}
    func editorBridge(_ bridge: EditorBridge, didChangeSelection selection: EditorSelectionState) {}
    func editorBridge(_ bridge: EditorBridge, didRequestOpenExternalLink url: URL) {}
    func editorBridge(_ bridge: EditorBridge, didRequestSaveAttachment payload: SaveAttachmentPayload) {}
    func editorBridge(_ bridge: EditorBridge, didRequestOpenAttachment payload: OpenAttachmentPayload) {}
    func editorBridge(_ bridge: EditorBridge, didReportError message: String) {}
}
