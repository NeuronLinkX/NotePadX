import Foundation

/// JSON의 임의 값을 표현하는 타입. attrs 같은 자유 형식 필드를 손실 없이 보존한다.
enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Double.self) {
            self = .number(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([String: JSONValue].self) {
            self = .object(v)
        } else if let v = try? container.decode([JSONValue].self) {
            self = .array(v)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

/// 알려진 블록 타입. 알 수 없는 타입은 EditorNode.type에 원문 문자열로 그대로 보존되어
/// 렌더러가 인식하지 못하더라도 문서 전체가 깨지지 않는다 (schema version fallback).
enum EditorNodeType: String, Sendable {
    case doc
    case paragraph
    case heading1, heading2, heading3, heading4, heading5, heading6
    case bulletList, orderedList, checklist, listItem
    case blockquote
    case codeBlock
    case table, tableRow, tableCell, tableHeaderCell
    case horizontalRule
    case details, detailsSummary, detailsContent
    case image
    case fileAttachment
}

enum EditorMarkType: String, Sendable {
    case bold, italic, underline, strike
    case superscript, subscript_ = "subscript"
    case textColor, highlight
    case fontSize, fontFamily, monospace, roman
    case link, code
}

struct EditorMark: Codable, Sendable, Equatable {
    var type: String
    var attrs: [String: JSONValue]?

    init(type: EditorMarkType, attrs: [String: JSONValue]? = nil) {
        self.type = type.rawValue
        self.attrs = attrs
    }

    init(rawType: String, attrs: [String: JSONValue]? = nil) {
        self.type = rawType
        self.attrs = attrs
    }
}

struct EditorNode: Codable, Sendable, Equatable {
    var type: String
    var attrs: [String: JSONValue]?
    var content: [EditorNode]?
    var text: String?
    var marks: [EditorMark]?

    init(
        type: EditorNodeType,
        attrs: [String: JSONValue]? = nil,
        content: [EditorNode]? = nil,
        text: String? = nil,
        marks: [EditorMark]? = nil
    ) {
        self.type = type.rawValue
        self.attrs = attrs
        self.content = content
        self.text = text
        self.marks = marks
    }

    /// 알 수 없는 노드 타입도 손실 없이 담을 수 있는 저수준 생성자.
    init(rawType: String, attrs: [String: JSONValue]? = nil, content: [EditorNode]? = nil, text: String? = nil, marks: [EditorMark]? = nil) {
        self.type = rawType
        self.attrs = attrs
        self.content = content
        self.text = text
        self.marks = marks
    }

    static func textNode(_ text: String, marks: [EditorMark]? = nil) -> EditorNode {
        EditorNode(rawType: "text", text: text, marks: marks)
    }

    static func paragraph(_ text: String) -> EditorNode {
        EditorNode(type: .paragraph, content: text.isEmpty ? [] : [.textNode(text)])
    }
}

struct EditorDocument: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var type: String
    var content: [EditorNode]

    init(schemaVersion: Int = EditorDocument.currentSchemaVersion, content: [EditorNode]) {
        self.schemaVersion = schemaVersion
        self.type = "doc"
        self.content = content
    }

    /// Phase 1 평문 편집기용: 줄바꿈 단위로 문단을 나눈 최소 구조 문서를 만든다.
    static func fromPlainText(_ plainText: String) -> EditorDocument {
        let paragraphs = plainText.isEmpty
            ? [EditorNode.paragraph("")]
            : plainText.components(separatedBy: "\n").map(EditorNode.paragraph)
        return EditorDocument(content: paragraphs)
    }

    /// 문서 트리에서 검색/미리보기용 순수 텍스트를 추출한다.
    var derivedPlainText: String {
        content.map { Self.extractText(from: $0) }.joined(separator: "\n")
    }

    private static func extractText(from node: EditorNode) -> String {
        if let text = node.text { return text }
        guard let children = node.content else { return "" }
        return children.map(extractText).joined(separator: node.type == "paragraph" ? "" : "\n")
    }
}

extension EditorDocument {
    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let jsonDecoder = JSONDecoder()

    func encoded() throws -> Data {
        try Self.jsonEncoder.encode(self)
    }

    static func decode(from data: Data) throws -> EditorDocument {
        try jsonDecoder.decode(EditorDocument.self, from: data)
    }
}
