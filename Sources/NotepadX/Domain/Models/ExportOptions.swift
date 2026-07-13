import CoreGraphics
import Foundation

enum ExportTheme: String, CaseIterable, Identifiable, Sendable {
    case light
    case dark
    var id: String { rawValue }
    var displayName: String { self == .light ? "밝게" : "어둡게" }
    var isDark: Bool { self == .dark }
}

enum ExportPageSize: String, CaseIterable, Identifiable, Sendable {
    case a4
    case letter
    case legal
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .a4: return "A4"
        case .letter: return "US Letter"
        case .legal: return "US Legal"
        }
    }
    /// 포인트(1/72인치) 단위 페이지 크기.
    var pointSize: CGSize {
        switch self {
        case .a4: return CGSize(width: 595, height: 842)
        case .letter: return CGSize(width: 612, height: 792)
        case .legal: return CGSize(width: 612, height: 1008)
        }
    }
}

enum ExportMargins: String, CaseIterable, Identifiable, Sendable {
    case narrow
    case normal
    case wide
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .narrow: return "좁게 (0.5\")"
        case .normal: return "보통 (1\")"
        case .wide: return "넓게 (1.5\")"
        }
    }
    /// 포인트 단위.
    var points: CGFloat {
        switch self {
        case .narrow: return 36
        case .normal: return 72
        case .wide: return 108
        }
    }
}

struct ExportOptions: Sendable, Equatable {
    var includeTitle: Bool = true
    var includeDates: Bool = false
    var codeBlockLineNumbers: Bool = false
    var theme: ExportTheme = .light
    var pageSize: ExportPageSize = .a4
    var margins: ExportMargins = .normal
    var includeHeaderFooter: Bool = false
    var author: String = ""
    var codeFont: String = "Menlo"
    var showTableBorders: Bool = true
}
