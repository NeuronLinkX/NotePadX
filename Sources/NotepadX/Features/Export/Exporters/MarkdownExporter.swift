import Foundation

/// EditorDocument(ProseMirror/Tiptap JSON 트리)를 순수 Swift로 직접 걸어서 Markdown으로 바꾼다.
/// HTML을 거치지 않는다 — 구조가 이미 트리로 있으니 문자열 파싱 없이 정확하게 변환할 수 있다.
enum MarkdownExporter {
    static func export(title: String, document: EditorDocument, note: Note?, options: ExportOptions) -> String {
        var lines: [String] = []

        if options.includeTitle, !title.isEmpty {
            lines.append("# \(title)")
            lines.append("")
        }
        if options.includeDates, let note {
            lines.append("_생성: \(DateFormatting.export.string(from: note.createdAt)) · 수정: \(DateFormatting.export.string(from: note.updatedAt))_")
            lines.append("")
        }

        for node in document.content {
            lines.append(contentsOf: renderBlock(node, options: options))
        }

        // 문단 사이 빈 줄이 3개 이상 겹치지 않도록 정리.
        return lines.joined(separator: "\n").replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
    }

    private static func renderBlock(_ node: EditorNode, listPrefix: String = "", options: ExportOptions) -> [String] {
        switch node.type {
        case "paragraph":
            let text = renderInline(node.content ?? [])
            return [listPrefix + text, ""]

        case "heading":
            let level = intAttr(node, "level") ?? 1
            let text = renderInline(node.content ?? [])
            return [String(repeating: "#", count: max(1, min(level, 6))) + " " + text, ""]

        case "bulletList":
            return (node.content ?? []).flatMap { renderListItem($0, marker: "- ", options: options) }

        case "orderedList":
            var index = 1
            var result: [String] = []
            for item in node.content ?? [] {
                result.append(contentsOf: renderListItem(item, marker: "\(index). ", options: options))
                index += 1
            }
            return result

        case "taskList":
            return (node.content ?? []).flatMap { item -> [String] in
                let checked = boolAttr(item, "checked") ?? false
                return renderListItem(item, marker: checked ? "- [x] " : "- [ ] ", options: options)
            }

        case "blockquote":
            let innerLines = (node.content ?? []).flatMap { renderBlock($0, options: options) }
            return innerLines.map { $0.isEmpty ? ">" : "> \($0)" } + [""]

        case "codeBlock":
            let language = stringAttr(node, "language") ?? ""
            let code = (node.content ?? []).map { $0.text ?? "" }.joined()
            var codeLines = code.components(separatedBy: "\n")
            if options.codeBlockLineNumbers {
                let width = String(codeLines.count).count
                codeLines = codeLines.enumerated().map { i, line in
                    String(format: "%\(width)d| %@", i + 1, line)
                }
            }
            return ["```\(language)"] + codeLines + ["```", ""]

        case "horizontalRule":
            return ["---", ""]

        case "details":
            let summary = (node.content ?? []).first { $0.type == "detailsSummary" }
            let content = (node.content ?? []).first { $0.type == "detailsContent" }
            var result = ["<details>", "<summary>" + renderInline(summary?.content ?? []) + "</summary>", ""]
            result.append(contentsOf: (content?.content ?? []).flatMap { renderBlock($0, options: options) })
            result.append("</details>")
            result.append("")
            return result

        case "table":
            return renderTable(node, options: options) + [""]

        case "image":
            let src = stringAttr(node, "src") ?? ""
            let alt = stringAttr(node, "alt") ?? ""
            return ["![\(alt)](\(src))", ""]

        case "fileAttachment":
            let fileName = stringAttr(node, "fileName") ?? "첨부파일"
            return ["📎 \(fileName)", ""]

        default:
            // 알 수 없는/미래 블록 타입은 텍스트만이라도 뽑아 문서가 깨지지 않게 한다.
            if let text = node.text { return [text, ""] }
            let childLines = (node.content ?? []).flatMap { renderBlock($0, options: options) }
            return childLines
        }
    }

    private static func renderListItem(_ item: EditorNode, marker: String, options: ExportOptions) -> [String] {
        let blocks = (item.content ?? []).flatMap { renderBlock($0, listPrefix: "", options: options) }
        guard let first = blocks.first else { return [marker.trimmingCharacters(in: .whitespaces)] }
        var result = [marker + first]
        let indent = String(repeating: " ", count: marker.count)
        for line in blocks.dropFirst() where !line.isEmpty {
            result.append(indent + line)
        }
        return result
    }

    private static func renderTable(_ node: EditorNode, options: ExportOptions) -> [String] {
        let rows = node.content ?? []
        guard !rows.isEmpty else { return [] }

        func cellText(_ cell: EditorNode) -> String {
            (cell.content ?? []).map { renderInline($0.content ?? []) }.joined(separator: " ")
        }

        let rendered = rows.map { row in (row.content ?? []).map(cellText) }
        guard let columnCount = rendered.first?.count, columnCount > 0 else { return [] }

        func rowLine(_ cells: [String]) -> String {
            "| " + cells.map { $0.replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |"
        }

        var lines = [rowLine(rendered[0])]
        lines.append("|" + Array(repeating: " --- ", count: columnCount).joined(separator: "|") + "|")
        for row in rendered.dropFirst() {
            lines.append(rowLine(row))
        }
        return lines
    }

    private static func renderInline(_ nodes: [EditorNode]) -> String {
        nodes.map { node -> String in
            if node.type == "hardBreak" { return "  \n" }
            guard var text = node.text else {
                return renderInline(node.content ?? [])
            }
            let markTypes = Set((node.marks ?? []).map(\.type))
            if markTypes.contains("code") {
                return "`\(text)`"
            }
            if markTypes.contains("bold") { text = "**\(text)**" }
            if markTypes.contains("italic") { text = "*\(text)*" }
            if markTypes.contains("strike") { text = "~~\(text)~~" }
            if let link = (node.marks ?? []).first(where: { $0.type == "link" }),
               case .string(let href)? = link.attrs?["href"] {
                text = "[\(text)](\(href))"
            }
            return text
        }.joined()
    }

    private static func stringAttr(_ node: EditorNode, _ key: String) -> String? {
        if case .string(let value)? = node.attrs?[key] { return value }
        return nil
    }

    private static func intAttr(_ node: EditorNode, _ key: String) -> Int? {
        if case .number(let value)? = node.attrs?[key] { return Int(value) }
        return nil
    }

    private static func boolAttr(_ node: EditorNode, _ key: String) -> Bool? {
        if case .bool(let value)? = node.attrs?[key] { return value }
        return nil
    }
}
