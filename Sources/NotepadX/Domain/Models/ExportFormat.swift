import Foundation

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case plainText
    case markdown
    case html
    case rtf
    case rtfd
    case pdf
    case docx
    case json

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plainText: return "Plain Text"
        case .markdown: return "Markdown"
        case .html: return "HTML"
        case .rtf: return "RTF"
        case .rtfd: return "RTFD"
        case .pdf: return "PDF"
        case .docx: return "Word 문서 (DOCX)"
        case .json: return "NotepadX JSON"
        }
    }

    var fileExtension: String {
        switch self {
        case .plainText: return "txt"
        case .markdown: return "md"
        case .html: return "html"
        case .rtf: return "rtf"
        case .rtfd: return "rtfd"
        case .pdf: return "pdf"
        case .docx: return "docx"
        case .json: return "json"
        }
    }

    var utType: String {
        switch self {
        case .plainText: return "public.plain-text"
        case .markdown: return "net.daringfireball.markdown"
        case .html: return "public.html"
        case .rtf: return "public.rtf"
        case .rtfd: return "com.apple.rtfd"
        case .pdf: return "com.adobe.pdf"
        case .docx: return "org.openxmlformats.wordprocessingml.document"
        case .json: return "public.json"
        }
    }
}
