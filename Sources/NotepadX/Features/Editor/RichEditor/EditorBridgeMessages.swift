import Foundation

/// JS → Swift로 넘어오는 메시지 중 처리할 것으로 명시적으로 허용한 이름만 나열한다.
/// 여기 없는 이름은 EditorBridge가 error로 되돌려 보내고 그냥 무시하지 않는다 (스펙 22절).
enum IncomingBridgeMessageType: String {
    case ready
    case docChanged
    case selectionChanged
    case openExternalLink
    case error
}

struct DocChangedPayload: Decodable {
    var schemaVersion: Int
    var type: String
    var content: [EditorNode]
    var plainText: String

    var document: EditorDocument {
        EditorDocument(schemaVersion: schemaVersion, content: content)
    }
}

struct EditorSelectionState: Decodable, Sendable, Equatable {
    var from: Int
    var to: Int
    var empty: Bool
    /// LLM 패널의 "선택 영역만 보내기" 범위에 쓴다.
    var selectedText: String
    var activeMarks: [String]
    var activeBlockType: String
    var headingLevel: Int?
    var codeBlockLanguage: String?
    var linkHref: String?
    var textColor: String?
    var fontSize: String?
}

struct OpenExternalLinkPayload: Decodable {
    var url: String
}

struct BridgeErrorPayload: Decodable {
    var message: String
}
