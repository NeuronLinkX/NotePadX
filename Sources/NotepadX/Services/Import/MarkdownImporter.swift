import Foundation

/// 가져오기로 만들어진 메모 하나. 제목과 본문은 편집기처럼 따로 둔다.
struct ImportedNote: Sendable, Equatable {
    var title: String
    var document: EditorDocument
    var plainText: String
}

/// Markdown(및 일반 텍스트)을 편집기 문서로 바꾼다. 자주 쓰는 문법(제목·목록·할 일·인용·코드·표·구분선·
/// 굵게/기울임/취소선/코드/링크)을 지원하고, 모르는 문법은 글자 그대로 남겨 내용이 사라지지 않게 한다.
/// 만드는 노드 이름은 실제 편집기(Tiptap)가 저장하는 것과 같다 — heading(level), bulletList/listItem,
/// taskList/taskItem, table/tableRow/tableHeader/tableCell, codeBlock, blockquote 등.
enum MarkdownImporter {
    static func parse(_ source: String, fallbackTitle: String) -> ImportedNote {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var blocks = parseBlocks(normalized.components(separatedBy: "\n")[...])

        // 첫 블록이 1단계 제목이면 그것을 메모 제목으로 쓰고 본문에서는 뺀다(제목이 두 번 나오지 않게).
        var title = fallbackTitle
        if let first = blocks.first, first.type == "heading", first.attrs?["level"] == .number(1) {
            let text = EditorDocument(content: [first]).derivedPlainText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                title = text
                blocks.removeFirst()
            }
        }
        if blocks.isEmpty { blocks = [EditorNode.paragraph("")] }
        let document = EditorDocument(content: blocks)
        return ImportedNote(title: title, document: document, plainText: document.derivedPlainText)
    }

    /// 일반 텍스트: 줄 하나가 문단 하나(빈 줄은 빈 문단)로 들어가고, 첫 비어 있지 않은 줄을 제목으로 삼지 않는다 —
    /// 파일 이름이 제목이 된다.
    static func parsePlainText(_ source: String, fallbackTitle: String) -> ImportedNote {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        let document = EditorDocument(content: lines.isEmpty ? [EditorNode.paragraph("")] : lines.map(EditorNode.paragraph))
        return ImportedNote(title: fallbackTitle, document: document, plainText: document.derivedPlainText)
    }

    // MARK: - 블록

    private static func parseBlocks(_ lines: ArraySlice<String>) -> [EditorNode] {
        var blocks: [EditorNode] = []
        var index = lines.startIndex

        func isBlank(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespaces).isEmpty }

        while index < lines.endIndex {
            let line = lines[index]
            if isBlank(line) { index += 1; continue }

            if let fence = fenceMarker(line) {
                var code: [String] = []
                index += 1
                while index < lines.endIndex, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence.marker) {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.endIndex { index += 1 }   // 닫는 펜스
                var attrs: [String: JSONValue]?
                if !fence.language.isEmpty { attrs = ["language": .string(fence.language)] }
                let text = code.joined(separator: "\n")
                blocks.append(EditorNode(type: .codeBlock, attrs: attrs, content: text.isEmpty ? nil : [.textNode(text)]))
                continue
            }

            if let heading = headingParts(line) {
                blocks.append(EditorNode(rawType: "heading", attrs: ["level": .number(Double(heading.level))], content: inline(heading.text)))
                index += 1
                continue
            }

            if isHorizontalRule(line) {
                blocks.append(EditorNode(type: .horizontalRule))
                index += 1
                continue
            }

            if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                var quoted: [String] = []
                while index < lines.endIndex, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    var content = lines[index].trimmingCharacters(in: .whitespaces)
                    content.removeFirst()
                    if content.hasPrefix(" ") { content.removeFirst() }
                    quoted.append(content)
                    index += 1
                }
                let inner = parseBlocks(quoted[...])
                blocks.append(EditorNode(type: .blockquote, content: inner.isEmpty ? [.paragraph("")] : inner))
                continue
            }

            if line.contains("|"), index + 1 < lines.endIndex, isTableSeparator(lines[index + 1]) {
                var rows: [[String]] = [tableCells(line)]
                index += 2
                while index < lines.endIndex, lines[index].contains("|"), !isBlank(lines[index]) {
                    rows.append(tableCells(lines[index]))
                    index += 1
                }
                blocks.append(tableNode(rows))
                continue
            }

            if listItemMarker(line) != nil {
                var listLines: [String] = []
                while index < lines.endIndex, !isBlank(lines[index]) || (index + 1 < lines.endIndex && listItemMarker(lines[index + 1]) != nil && !isBlank(lines[index])) {
                    if isBlank(lines[index]) { break }
                    // 목록 안의 다른 블록(코드·제목 등)이 시작되면 목록은 거기서 끝난다.
                    if listItemMarker(lines[index]) == nil, indentWidth(lines[index]) == 0 { break }
                    listLines.append(lines[index])
                    index += 1
                }
                blocks.append(contentsOf: buildLists(listLines))
                continue
            }

            // 문단: 다른 블록이 시작하기 전까지의 연속된 줄.
            var paragraphLines: [String] = []
            while index < lines.endIndex, !isBlank(lines[index]) {
                if !paragraphLines.isEmpty, startsNewBlock(lines[index], next: index + 1 < lines.endIndex ? lines[index + 1] : nil) { break }
                paragraphLines.append(lines[index])
                index += 1
            }
            blocks.append(EditorNode(type: .paragraph, content: paragraphInline(paragraphLines)))
        }
        return blocks
    }

    private static func startsNewBlock(_ line: String, next: String?) -> Bool {
        if fenceMarker(line) != nil || headingParts(line) != nil || isHorizontalRule(line) { return true }
        if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") { return true }
        if listItemMarker(line) != nil { return true }
        if line.contains("|"), let next, isTableSeparator(next) { return true }
        return false
    }

    private static func fenceMarker(_ line: String) -> (marker: String, language: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["```", "~~~"] where trimmed.hasPrefix(marker) {
            return (marker, String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private static func headingParts(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.first == " " || rest.first == "\t" else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // 닫는 # 은 제거(예: "## 제목 ##")
        while text.hasSuffix("#") { text.removeLast() }
        return (hashes.count, text.trimmingCharacters(in: .whitespaces))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    // MARK: - 표

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = tableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            return c.count >= 3 && c.allSatisfy { $0 == "-" || $0 == ":" } && c.contains("-")
        }
    }

    private static func tableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func tableNode(_ rows: [[String]]) -> EditorNode {
        let columnCount = rows.map(\.count).max() ?? 1
        func cell(_ text: String, header: Bool) -> EditorNode {
            EditorNode(rawType: header ? "tableHeader" : "tableCell", content: [EditorNode(type: .paragraph, content: inline(text))])
        }
        let tableRows = rows.enumerated().map { rowIndex, cells -> EditorNode in
            let padded = cells + Array(repeating: "", count: columnCount - cells.count)
            return EditorNode(rawType: "tableRow", content: padded.map { cell($0, header: rowIndex == 0) })
        }
        return EditorNode(rawType: "table", content: tableRows)
    }

    // MARK: - 목록

    private struct ListMarker {
        let indent: Int
        let ordered: Bool
        let task: Bool?       // nil = 일반 항목, true/false = 할 일(체크 여부)
        let text: String
    }

    private static func indentWidth(_ line: String) -> Int {
        var width = 0
        for ch in line {
            if ch == " " { width += 1 } else if ch == "\t" { width += 4 } else { break }
        }
        return width
    }

    private static func listItemMarker(_ line: String) -> ListMarker? {
        let indent = indentWidth(line)
        let body = line.drop { $0 == " " || $0 == "\t" }
        var ordered = false
        var rest: Substring
        if let first = body.first, "-*+".contains(first), body.dropFirst().first == " " {
            // "---" 같은 구분선과 구별: 위에서 이미 구분선을 먼저 걸러낸다.
            rest = body.dropFirst(2)
        } else {
            let digits = body.prefix { $0.isNumber }
            guard !digits.isEmpty, digits.count <= 9 else { return nil }
            let after = body.dropFirst(digits.count)
            guard let punct = after.first, punct == "." || punct == ")", after.dropFirst().first == " " else { return nil }
            ordered = true
            rest = after.dropFirst(2)
        }
        var task: Bool?
        let trimmedRest = rest.drop { $0 == " " }
        if trimmedRest.hasPrefix("[ ] ") || trimmedRest == "[ ]" { task = false; rest = trimmedRest.dropFirst(min(4, trimmedRest.count)) }
        else if trimmedRest.lowercased().hasPrefix("[x] ") || trimmedRest.lowercased() == "[x]" { task = true; rest = trimmedRest.dropFirst(min(4, trimmedRest.count)) }
        return ListMarker(indent: indent, ordered: ordered, task: task, text: String(rest))
    }

    /// 들여쓰기로 중첩된 목록 줄들을 목록 노드 트리로 만든다. 같은 수준에서 종류(순서/글머리/할 일)가
    /// 바뀌면 별도 목록으로 나눈다.
    private static func buildLists(_ lines: [String]) -> [EditorNode] {
        let markers = lines.compactMap(listItemMarker)
        var cursor = 0

        func build(minIndent: Int) -> [EditorNode] {
            var result: [EditorNode] = []
            var items: [EditorNode] = []
            var currentKind: (ordered: Bool, task: Bool)?

            func flush() {
                guard let kind = currentKind, !items.isEmpty else { return }
                let type = kind.task ? "taskList" : (kind.ordered ? "orderedList" : "bulletList")
                result.append(EditorNode(rawType: type, content: items))
                items = []
            }

            while cursor < markers.count {
                let marker = markers[cursor]
                if marker.indent < minIndent { break }
                let kind = (ordered: marker.ordered, task: marker.task != nil)
                if let existing = currentKind, existing != kind { flush() }
                currentKind = kind
                cursor += 1

                var itemContent: [EditorNode] = [EditorNode(type: .paragraph, content: inline(marker.text))]
                if cursor < markers.count, markers[cursor].indent > marker.indent {
                    itemContent.append(contentsOf: build(minIndent: markers[cursor].indent))
                }
                if let checked = marker.task {
                    items.append(EditorNode(rawType: "taskItem", attrs: ["checked": .bool(checked)], content: itemContent))
                } else {
                    items.append(EditorNode(type: .listItem, content: itemContent))
                }
            }
            flush()
            return result
        }

        var all: [EditorNode] = []
        while cursor < markers.count { all.append(contentsOf: build(minIndent: markers[cursor].indent)) }
        return all
    }

    // MARK: - 인라인

    private static func paragraphInline(_ lines: [String]) -> [EditorNode] {
        var nodes: [EditorNode] = []
        for (offset, line) in lines.enumerated() {
            var text = line.trimmingCharacters(in: .init(charactersIn: " \t"))
            // 줄 끝의 공백 두 개 또는 역슬래시는 강제 줄바꿈이다. 그 밖의 줄바꿈은 공백으로 이어 붙인다.
            let hardBreak = line.hasSuffix("  ") || line.hasSuffix("\\")
            if text.hasSuffix("\\") { text.removeLast() }
            nodes.append(contentsOf: inline(text))
            if offset < lines.count - 1 {
                if hardBreak { nodes.append(EditorNode(rawType: "hardBreak")) } else { nodes.append(.textNode(" ")) }
            }
        }
        return merge(nodes)
    }

    static func inline(_ text: String) -> [EditorNode] {
        merge(parseInline(Array(text), marks: []))
    }

    private static func parseInline(_ chars: [Character], marks: [EditorMark]) -> [EditorNode] {
        var nodes: [EditorNode] = []
        var buffer = ""
        var i = 0

        func flush() {
            if !buffer.isEmpty { nodes.append(.textNode(buffer, marks: marks.isEmpty ? nil : marks)); buffer = "" }
        }
        func find(_ pattern: [Character], from start: Int) -> Int? {
            guard !pattern.isEmpty, chars.count >= pattern.count else { return nil }
            var j = start
            while j + pattern.count <= chars.count {
                if Array(chars[j..<(j + pattern.count)]) == pattern { return j }
                j += 1
            }
            return nil
        }

        while i < chars.count {
            let ch = chars[i]

            if ch == "\\", i + 1 < chars.count, "\\`*_{}[]()#+-.!~|>".contains(chars[i + 1]) {
                buffer.append(chars[i + 1]); i += 2; continue
            }

            if ch == "`" {
                let ticks = chars[i...].prefix { $0 == "`" }.count
                let fence = Array(repeating: Character("`"), count: ticks)
                if let close = find(fence, from: i + ticks) {
                    flush()
                    let code = String(chars[(i + ticks)..<close]).trimmingCharacters(in: .whitespaces)
                    nodes.append(.textNode(code, marks: marks + [EditorMark(type: .code)]))
                    i = close + ticks
                    continue
                }
            }

            if (ch == "*" || ch == "_"), i + 1 < chars.count, chars[i + 1] == ch,
               let close = find([ch, ch], from: i + 2), close > i + 2, boundaryOK(chars, i, ch) {
                flush()
                nodes.append(contentsOf: parseInline(Array(chars[(i + 2)..<close]), marks: marks + [EditorMark(type: .bold)]))
                i = close + 2
                continue
            }

            if ch == "~", i + 1 < chars.count, chars[i + 1] == "~", let close = find(["~", "~"], from: i + 2), close > i + 2 {
                flush()
                nodes.append(contentsOf: parseInline(Array(chars[(i + 2)..<close]), marks: marks + [EditorMark(type: .strike)]))
                i = close + 2
                continue
            }

            if (ch == "*" || ch == "_"), i + 1 < chars.count, chars[i + 1] != " ",
               let close = findSingle(chars, ch, from: i + 1), close > i + 1, boundaryOK(chars, i, ch) {
                flush()
                nodes.append(contentsOf: parseInline(Array(chars[(i + 1)..<close]), marks: marks + [EditorMark(type: .italic)]))
                i = close + 1
                continue
            }

            if ch == "!" || ch == "[" {
                let isImage = ch == "!"
                let open = isImage ? i + 1 : i
                if open < chars.count, chars[open] == "[", let closeBracket = find(["]", "("], from: open + 1),
                   let closeParen = find([")"], from: closeBracket + 2) {
                    let label = String(chars[(open + 1)..<closeBracket])
                    let url = String(chars[(closeBracket + 2)..<closeParen]).split(separator: " ").first.map(String.init) ?? ""
                    flush()
                    let shownText = label.isEmpty ? url : label
                    let prefixed = isImage ? "🖼 " + shownText : shownText
                    var linkMarks = marks
                    if !url.isEmpty { linkMarks.append(EditorMark(type: .link, attrs: ["href": .string(url)])) }
                    nodes.append(.textNode(prefixed, marks: linkMarks.isEmpty ? nil : linkMarks))
                    i = closeParen + 1
                    continue
                }
            }

            buffer.append(ch)
            i += 1
        }
        flush()
        return nodes
    }

    private static func findSingle(_ chars: [Character], _ marker: Character, from start: Int) -> Int? {
        var j = start
        while j < chars.count {
            if chars[j] == "\\" { j += 2; continue }
            if chars[j] == marker, (j + 1 >= chars.count || chars[j + 1] != marker), chars[j - 1] != " " { return j }
            j += 1
        }
        return nil
    }

    /// `snake_case_name`처럼 낱말 가운데의 밑줄을 강조로 오해하지 않는다.
    private static func boundaryOK(_ chars: [Character], _ index: Int, _ marker: Character) -> Bool {
        guard marker == "_" else { return true }
        guard index > 0 else { return true }
        let previous = chars[index - 1]
        return !(previous.isLetter || previous.isNumber)
    }

    /// 같은 서식이 이어지는 글자 노드를 하나로 합친다.
    private static func merge(_ nodes: [EditorNode]) -> [EditorNode] {
        var merged: [EditorNode] = []
        for node in nodes {
            if let last = merged.last, last.type == "text", node.type == "text", last.marks == node.marks {
                merged[merged.count - 1].text = (last.text ?? "") + (node.text ?? "")
            } else {
                merged.append(node)
            }
        }
        return merged.filter { $0.type != "text" || !($0.text ?? "").isEmpty }
    }
}
