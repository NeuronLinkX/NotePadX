import Foundation
@preconcurrency import WebKit

@MainActor
protocol EditorBridgeDelegate: AnyObject {
    func editorBridgeDidBecomeReady(_ bridge: EditorBridge)
    func editorBridge(_ bridge: EditorBridge, didChangeDocument document: EditorDocument, plainText: String)
    func editorBridge(_ bridge: EditorBridge, didChangeSelection selection: EditorSelectionState)
    func editorBridge(_ bridge: EditorBridge, didRequestOpenExternalLink url: URL)
    func editorBridge(_ bridge: EditorBridge, didReportError message: String)
}

/// WKWebView 안의 Tiptap 에디터와 Swift를 연결하는 유일한 통로.
/// `userContentController(_:didReceive:)`로 들어오는 메시지는 정해진 이름(type)만 처리하고,
/// 그 외는 조용히 무시하지 않고 델리게이트로 오류를 되돌려 보낸다 (스펙 22절).
@MainActor
final class EditorBridge: NSObject, WKScriptMessageHandler {
    static let messageHandlerName = "notepadXBridge"

    weak var delegate: EditorBridgeDelegate?
    weak var webView: WKWebView?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName else { return }
        dispatch(body: message.body)
    }

    private func dispatch(body: Any) {
        guard let dict = body as? [String: Any], let typeString = dict["type"] as? String else {
            delegate?.editorBridge(self, didReportError: "Malformed bridge message")
            return
        }
        guard let messageType = IncomingBridgeMessageType(rawValue: typeString) else {
            delegate?.editorBridge(self, didReportError: "Unknown bridge message: \(typeString)")
            return
        }

        let rawPayload = dict["payload"] ?? [String: Any]()
        let normalizedPayload: Any = (rawPayload is NSNull) ? [String: Any]() : rawPayload
        guard JSONSerialization.isValidJSONObject(normalizedPayload),
              let payloadData = try? JSONSerialization.data(withJSONObject: normalizedPayload) else {
            delegate?.editorBridge(self, didReportError: "Malformed payload for \(typeString)")
            return
        }

        switch messageType {
        case .ready:
            delegate?.editorBridgeDidBecomeReady(self)

        case .docChanged:
            guard let payload = try? JSONDecoder().decode(DocChangedPayload.self, from: payloadData) else {
                delegate?.editorBridge(self, didReportError: "Failed to decode docChanged payload")
                return
            }
            delegate?.editorBridge(self, didChangeDocument: payload.document, plainText: payload.plainText)

        case .selectionChanged:
            guard let payload = try? JSONDecoder().decode(EditorSelectionState.self, from: payloadData) else {
                delegate?.editorBridge(self, didReportError: "Failed to decode selectionChanged payload")
                return
            }
            delegate?.editorBridge(self, didChangeSelection: payload)

        case .openExternalLink:
            guard let payload = try? JSONDecoder().decode(OpenExternalLinkPayload.self, from: payloadData),
                  let url = URL(string: payload.url),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme) else {
                delegate?.editorBridge(self, didReportError: "Rejected external link request")
                return
            }
            delegate?.editorBridge(self, didRequestOpenExternalLink: url)

        case .error:
            let message = (try? JSONDecoder().decode(BridgeErrorPayload.self, from: payloadData))?.message ?? "unknown error"
            delegate?.editorBridge(self, didReportError: message)
        }
    }

    // MARK: - Swift -> JS

    func loadDocument(_ document: EditorDocument) {
        guard let data = try? document.encoded(), let json = String(data: data, encoding: .utf8) else { return }
        evaluate("window.NotepadXBridge && window.NotepadXBridge.loadDocument(\(json));")
    }

    func applyCommand(_ name: String, args: [String: Any]? = nil) {
        evaluate("window.NotepadXBridge && window.NotepadXBridge.applyCommand(\(Self.jsStringLiteral(name)), \(Self.jsonLiteral(for: args)));")
    }

    func setTheme(isDark: Bool) {
        evaluate("window.NotepadXBridge && window.NotepadXBridge.setTheme({ isDark: \(isDark) });")
    }

    func setEditable(_ isEditable: Bool) {
        evaluate("window.NotepadXBridge && window.NotepadXBridge.setEditable(\(isEditable));")
    }

    func focusEditor() {
        evaluate("window.NotepadXBridge && window.NotepadXBridge.focusEditor();")
    }

    private func evaluate(_ script: String) {
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Swift String을 안전하게 이스케이프된 JS 문자열 리터럴로 변환한다 (JSON 문자열 인코딩 재사용).
    private static func jsStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value), let string = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return string
    }

    /// JSON 문법은 JS 리터럴 문법의 부분집합이므로, 직렬화한 JSON 텍스트를 그대로
    /// evaluateJavaScript 문자열에 끼워 넣어 JS 쪽에서 파싱 없이 객체로 받게 한다.
    private static func jsonLiteral(for dict: [String: Any]?) -> String {
        guard let dict, JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return string
    }
}
