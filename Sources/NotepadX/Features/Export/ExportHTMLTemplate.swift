import Foundation

/// DocumentHTMLRenderer가 만든 본문 조각을, 제목/메타데이터/인쇄용 CSS를 갖춘
/// 완전한 독립 HTML 문서로 감싼다. HTML 내보내기 자체의 결과물이자, PDF/RTF 변환의 입력이다.
enum ExportHTMLTemplate {
    static func wrap(title: String, bodyFragment: String, note: Note?, options: ExportOptions) -> String {
        let css = (try? String(
            contentsOf: WebEditorResources.webEditorDirectoryURL!.appendingPathComponent("editor.css"),
            encoding: .utf8
        )) ?? ""

        var header = ""
        if options.includeTitle, !title.isEmpty {
            header += "<h1 class=\"nx-export-title\">\(HTMLEscape.escape(title))</h1>\n"
        }
        if options.includeDates, let note {
            let text = "생성: \(DateFormatting.export.string(from: note.createdAt))  ·  수정: \(DateFormatting.export.string(from: note.updatedAt))"
            header += "<p class=\"nx-export-meta\">\(HTMLEscape.escape(text))</p>\n"
        }
        if !options.author.isEmpty {
            header += "<p class=\"nx-export-meta\">작성자: \(HTMLEscape.escape(options.author))</p>\n"
        }

        var footer = ""
        if options.includeHeaderFooter {
            footer = "<footer class=\"nx-export-footer\">NotepadX</footer>"
        }

        let themeAttr = options.theme.isDark ? "dark" : "light"
        let marginInches = options.margins.points / 72
        let pageSizeKeyword: String
        switch options.pageSize {
        case .a4: pageSizeKeyword = "A4"
        case .letter: pageSizeKeyword = "letter"
        case .legal: pageSizeKeyword = "legal"
        }

        return """
        <!doctype html>
        <html lang="ko" data-theme="\(themeAttr)">
        <head>
        <meta charset="utf-8" />
        <title>\(HTMLEscape.escape(title.isEmpty ? "NotepadX" : title))</title>
        <style>
        \(css)
        @page { size: \(pageSizeKeyword); margin: \(marginInches)in; }
        body { padding: 28px 36px; }
        .nx-export-title { margin: 0 0 4px; }
        .nx-export-meta { color: var(--nx-text-secondary); font-size: 0.85em; margin: 2px 0; }
        .nx-export-footer { margin-top: 24px; padding-top: 8px; border-top: 1px solid var(--nx-border); color: var(--nx-text-secondary); font-size: 0.8em; text-align: center; }
        </style>
        </head>
        <body data-theme="\(themeAttr)">
        \(header)
        <div class="ProseMirror">
        \(bodyFragment)
        </div>
        \(footer)
        </body>
        </html>
        """
    }
}
