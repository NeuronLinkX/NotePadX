import Foundation

/// JS → Swift로 넘어오는 메시지 중 처리할 것으로 명시적으로 허용한 이름만 나열한다.
/// 여기 없는 이름은 EditorBridge가 error로 되돌려 보내고 그냥 무시하지 않는다 (스펙 22절).
enum IncomingBridgeMessageType: String {
    case ready
    case docChanged
    case headingsChanged
    case selectionChanged
    case openExternalLink
    case saveAttachment
    case openAttachment
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

/// 문서 개요(왼쪽 패널) 한 항목. `pos`는 ProseMirror 문서 안의 위치로, Swift 쪽에서는
/// 의미를 해석하지 않고 `scrollToHeading` 커맨드의 인자로 그대로 되돌려 보낸다 — 그래야
/// 실제 위치 계산 규칙(노드 경계 +1 등)을 JS/ProseMirror 쪽 한 곳에서만 유지한다.
struct HeadingOutlineItem: Decodable, Sendable, Equatable {
    var pos: Int
    var level: Int
    var text: String
}

struct HeadingsChangedPayload: Decodable {
    var headings: [HeadingOutlineItem]
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

/// 이미지가 아닌 파일을 드래그·붙여넣기 했을 때 JS가 base64로 인코딩해 보낸다. `attachmentId`는
/// JS가 미리 만들어(crypto.randomUUID) 문서에 fileAttachment 노드로 함께 삽입해 둔 값과
/// 같다 — Swift는 그 id로 디스크에 파일만 저장하면 되고, 문서 쪽 왕복은 이미 끝나 있다.
struct SaveAttachmentPayload: Decodable {
    var attachmentId: String
    var fileName: String
    var mimeType: String
    var base64Data: String
}

/// 첨부파일 카드를 클릭했을 때. Swift가 attachmentId로 실제 저장 경로를 찾아 기본 앱으로 연다.
struct OpenAttachmentPayload: Decodable {
    var attachmentId: String
    var fileName: String
}

struct BridgeErrorPayload: Decodable {
    var message: String
}
