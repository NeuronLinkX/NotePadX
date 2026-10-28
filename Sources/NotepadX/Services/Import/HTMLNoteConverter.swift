import Foundation

/// 메모 앱이 AppleScript로 내주는 HTML 본문을 편집기 문서로 바꾼다. 메모의 HTML은 XML처럼 엄격하지 않아
/// (`<br>`이 닫히지 않는다) 관대한 작은 토크나이저로 트리를 만든 뒤 변환한다.
/// 지원: h1~h6, div/p, br, ul/ol/li(중첩), b/strong, i/em, u, s/strike/del, a, code/tt/pre, 표, 데이터 URI 그림.
enum HTMLNoteConverter {
    // MARK: - 트리

    private final class Element {
        let tag: String
        var attributes: [String: String]
        var children: [Child] = []
        weak var parent: Element?
        init(tag: String, attributes: [String: String] = [:]) {
            self.tag = tag
            self.attributes = attributes
        }
    }

    private enum Child {
        case text(String)
        case element(Element)
    }

    private static let voidTags: Set<String> = ["br", "img", "hr", "meta", "link", "input"]

    private static func parse(_ html: String) -> Element {
        let root = Element(tag: "#root")
        var current = root
        let chars = Array(html)
        var i = 0
        var text = ""

        func flushText() {
            if !text.isEmpty { current.children.append(.text(decodeEntities(text))); text = "" }
        }

        while i < chars.count {
            guard chars[i] == "<" else { text.append(chars[i]); i += 1; continue }
            // 주석
            if i + 3 < chars.count, String(chars[i..<(i + 4)]) == "<!--" {
                var j = i + 4
                while j + 2 < chars.count, String(chars[j..<(j + 3)]) != "-->" { j += 1 }
                i = min(chars.count, j + 3)
                continue
            }
            guard let close = chars[i...].firstIndex(of: ">") else { text.append(chars[i]); i += 1; continue }
            let inside = String(chars[(i + 1)..<close])
            i = close + 1

            if inside.hasPrefix("!") || inside.hasPrefix("?") { continue }
            if inside.hasPrefix("/") {
                flushText()
                let name = inside.dropFirst().trimmingCharacters(in: .whitespaces).lowercased()
                // 열려 있는 가장 가까운 같은 이름의 요소까지 닫는다(어긋난 HTML 대비).
                var node: Element? = current
                while let n = node, n.tag != name, n.tag != "#root" { node = n.parent }
                if let n = node, n.tag == name, let parent = n.parent { current = parent }
                continue
            }
            flushText()
            let selfClosing = inside.hasSuffix("/")
            let (name, attributes) = parseTag(selfClosing ? String(inside.dropLast()) : inside)
            let element = Element(tag: name, attributes: attributes)
            element.parent = current
            current.children.append(.element(element))
            if name == "script" || name == "style" {
                // 내용을 통째로 건너뛴다.
                let closer = "</\(name)"
                var j = i
                while j < chars.count {
                    if chars[j] == "<", j + closer.count <= chars.count, String(chars[j..<(j + closer.count)]).lowercased() == closer { break }
                    j += 1
                }
                if let end = chars[min(j, chars.count - 1)...].firstIndex(of: ">") { i = end + 1 } else { i = chars.count }
                continue
            }
            if !selfClosing, !voidTags.contains(name) { current = element }
        }
        flushText()
        return root
    }

    private static func parseTag(_ raw: String) -> (String, [String: String]) {
        let scalars = Array(raw)
        var i = 0
        var name = ""
        while i < scalars.count, !scalars[i].isWhitespace { name.append(scalars[i]); i += 1 }
        var attributes: [String: String] = [:]
        while i < scalars.count {
            while i < scalars.count, scalars[i].isWhitespace { i += 1 }
            var key = ""
            while i < scalars.count, scalars[i] != "=", !scalars[i].isWhitespace { key.append(scalars[i]); i += 1 }
            while i < scalars.count, scalars[i].isWhitespace { i += 1 }
            var value = ""
            if i < scalars.count, scalars[i] == "=" {
                i += 1
                while i < scalars.count, scalars[i].isWhitespace { i += 1 }
                if i < scalars.count, scalars[i] == "\"" || scalars[i] == "'" {
                    let quote = scalars[i]; i += 1
                    while i < scalars.count, scalars[i] != quote { value.append(scalars[i]); i += 1 }
                    i += 1
                } else {
                    while i < scalars.count, !scalars[i].isWhitespace { value.append(scalars[i]); i += 1 }
                }
            }
            if !key.isEmpty { attributes[key.lowercased()] = decodeEntities(value) }
        }
        return (name.lowercased(), attributes)
    }

    private static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var index = s.startIndex
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—", "hellip": "…"]
        while index < s.endIndex {
            if s[index] == "&", let semi = s[index...].firstIndex(of: ";"), s.distance(from: index, to: semi) <= 10 {
                let entity = String(s[s.index(after: index)..<semi])
                if let value = named[entity] { out += value; index = s.index(after: semi); continue }
                if entity.hasPrefix("#") {
                    let digits = entity.dropFirst()
                    let code = digits.lowercased().hasPrefix("x") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                    if let code, let scalar = Unicode.Scalar(code) { out.unicodeScalars.append(scalar); index = s.index(after: semi); continue }
                }
            }
            out.append(s[index])
            index = s.index(after: index)
        }
        return out
    }

    // MARK: - 변환

    static func convert(html: String) -> [EditorNode] {
        convert(root: parse(html))
    }

    private static func convert(root: Element) -> [EditorNode] {
        var blocks: [EditorNode] = []
        var inline: [EditorNode] = []

        func flushInline() {
            let trimmed = trimEdges(merge(inline))
            inline = []
            guard !trimmed.isEmpty else { return }
            blocks.append(EditorNode(type: .paragraph, content: trimmed))
        }

        func walk(_ element: Element, marks: [EditorMark]) {
            for child in element.children {
                switch child {
                case .text(let raw):
                    let collapsed = collapseWhitespace(raw)
                    if !collapsed.isEmpty { inline.append(.textNode(collapsed, marks: marks.isEmpty ? nil : marks)) }
                case .element(let el):
                    handle(el, marks: marks)
                }
            }
        }

        func handle(_ el: Element, marks: [EditorMark]) {
            switch el.tag {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                flushInline()
                let saved = inline; inline = []
                walk(el, marks: marks)
                let content = trimEdges(merge(inline)); inline = saved
                if !content.isEmpty {
                    blocks.append(EditorNode(rawType: "heading", attrs: ["level": .number(Double(el.tag.dropFirst()) ?? 1)], content: content))
                }
            case "div", "p", "section", "article", "body", "html", "span", "font", "main", "header", "footer", "#root":
                let block = ["div", "p", "section", "article"].contains(el.tag)
                if block { flushInline() }
                if el.tag == "div" || el.tag == "p", el.children.isEmpty || isOnlyBreak(el) {
                    blocks.append(EditorNode(type: .paragraph))   // 메모 앱의 빈 줄
                } else {
                    walk(el, marks: marks)
                }
                if block { flushInline() }
            case "br":
                inline.append(EditorNode(rawType: "hardBreak"))
            case "b", "strong": walk(el, marks: marks + [EditorMark(type: .bold)])
            case "i", "em": walk(el, marks: marks + [EditorMark(type: .italic)])
            case "u": walk(el, marks: marks + [EditorMark(type: .underline)])
            case "s", "strike", "del": walk(el, marks: marks + [EditorMark(type: .strike)])
            case "code", "tt", "kbd": walk(el, marks: marks + [EditorMark(type: .code)])
            case "sup": walk(el, marks: marks + [EditorMark(type: .superscript)])
            case "sub": walk(el, marks: marks + [EditorMark(type: .subscript_)])
            case "a":
                if let href = el.attributes["href"], !href.isEmpty {
                    walk(el, marks: marks + [EditorMark(type: .link, attrs: ["href": .string(href)])])
                } else {
                    walk(el, marks: marks)
                }
            case "pre":
                flushInline()
                let text = plainText(of: el)
                blocks.append(EditorNode(type: .codeBlock, content: text.isEmpty ? nil : [.textNode(text)]))
            case "blockquote":
                flushInline()
                let saved = blocks; blocks = []
                walk(el, marks: marks); flushInline()
                let inner = blocks; blocks = saved
                blocks.append(EditorNode(type: .blockquote, content: inner.isEmpty ? [.paragraph("")] : inner))
            case "ul", "ol":
                flushInline()
                if let list = listNode(el) { blocks.append(list) }
            case "table":
                flushInline()
                if let table = tableNode(el) { blocks.append(table) }
            case "hr":
                flushInline()
                blocks.append(EditorNode(type: .horizontalRule))
            case "img":
                if let src = el.attributes["src"], src.hasPrefix("data:image/") {
                    flushInline()
                    blocks.append(EditorNode(rawType: "image", attrs: ["src": .string(src)]))
                }
            case "script", "style", "head", "title", "meta": break
            default:
                walk(el, marks: marks)
            }
        }

        handle(root, marks: [])
        flushInline()
        return blocks
    }

    private static func isOnlyBreak(_ el: Element) -> Bool {
        el.children.allSatisfy { child in
            switch child {
            case .element(let e): return e.tag == "br"
            case .text(let t): return t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    private static func listNode(_ list: Element) -> EditorNode? {
        let ordered = list.tag == "ol"
        var items: [EditorNode] = []
        for case .element(let li) in list.children where li.tag == "li" {
            // 항목 안의 글과 중첩 목록을 나눠 담는다.
            let inlineHolder = Element(tag: "span")
            var nested: [EditorNode] = []
            for child in li.children {
                if case .element(let e) = child, e.tag == "ul" || e.tag == "ol" {
                    if let inner = listNode(e) { nested.append(inner) }
                } else {
                    inlineHolder.children.append(child)
                }
            }
            let text = convert(inlineOnly: inlineHolder)
            items.append(EditorNode(type: .listItem, content: [EditorNode(type: .paragraph, content: text)] + nested))
        }
        guard !items.isEmpty else { return nil }
        return EditorNode(rawType: ordered ? "orderedList" : "bulletList", content: items)
    }

    private static func convert(inlineOnly element: Element) -> [EditorNode] {
        // 요소 하나를 문서로 변환한 뒤 문단들의 글자 노드만 이어 붙인다(목록 항목의 글).
        let wrapper = Element(tag: "#root")
        wrapper.children = [.element(element)]
        var inline: [EditorNode] = []
        for block in convert(root: wrapper) {
            if !inline.isEmpty { inline.append(EditorNode(rawType: "hardBreak")) }
            inline.append(contentsOf: block.content ?? [])
        }
        return merge(inline)
    }

    private static func tableNode(_ table: Element) -> EditorNode? {
        var rows: [[Element]] = []
        func collect(_ e: Element) {
            for case .element(let child) in e.children {
                if child.tag == "tr" {
                    rows.append(child.children.compactMap { if case .element(let c) = $0, c.tag == "td" || c.tag == "th" { return c } else { return nil } })
                } else if child.tag == "tbody" || child.tag == "thead" || child.tag == "tfoot" {
                    collect(child)
                }
            }
        }
        collect(table)
        guard !rows.isEmpty else { return nil }
        let columns = rows.map(\.count).max() ?? 1
        let tableRows = rows.enumerated().map { index, cells -> EditorNode in
            var nodes = cells.map { cell -> EditorNode in
                let wrapper = Element(tag: "#root")
                wrapper.children = cell.children
                var content = convert(root: wrapper)
                if content.isEmpty { content = [EditorNode(type: .paragraph)] }
                return EditorNode(rawType: index == 0 ? "tableHeader" : "tableCell", content: content)
            }
            while nodes.count < columns {
                nodes.append(EditorNode(rawType: index == 0 ? "tableHeader" : "tableCell", content: [EditorNode(type: .paragraph)]))
            }
            return EditorNode(rawType: "tableRow", content: nodes)
        }
        return EditorNode(rawType: "table", content: tableRows)
    }

    private static func plainText(of element: Element) -> String {
        element.children.map { child -> String in
            switch child {
            case .text(let t): return t
            case .element(let e): return e.tag == "br" ? "\n" : plainText(of: e)
            }
        }.joined()
    }

    private static func collapseWhitespace(_ s: String) -> String {
        var out = ""
        var previousSpace = false
        for ch in s {
            if ch == "\n" || ch == "\r" || ch == "\t" || ch == " " {
                if !previousSpace { out.append(" ") }
                previousSpace = true
            } else {
                out.append(ch)
                previousSpace = false
            }
        }
        return out
    }

    private static func trimEdges(_ nodes: [EditorNode]) -> [EditorNode] {
        var result = nodes
        while let first = result.first, first.type == "text", (first.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty { result.removeFirst() }
        while let last = result.last, last.type == "text", (last.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty { result.removeLast() }
        while let last = result.last, last.type == "hardBreak" { result.removeLast() }
        if var first = result.first, first.type == "text", let text = first.text, text.hasPrefix(" ") {
            first.text = String(text.drop { $0 == " " }); result[0] = first
        }
        if var last = result.last, last.type == "text", let text = last.text, text.hasSuffix(" ") {
            var trimmed = text
            while trimmed.hasSuffix(" ") { trimmed.removeLast() }
            last.text = trimmed; result[result.count - 1] = last
        }
        return result
    }

    private static func merge(_ nodes: [EditorNode]) -> [EditorNode] {
        var merged: [EditorNode] = []
        for node in nodes {
            if let last = merged.last, last.type == "text", node.type == "text", last.marks == node.marks {
                merged[merged.count - 1].text = (last.text ?? "") + (node.text ?? "")
            } else {
                merged.append(node)
            }
        }
        return merged
    }

    /// 메모 한 개를 가져온 결과로 만든다. 첫 비어 있지 않은 블록이 제목(메모 앱이 첫 줄을 제목으로 쓴다).
    static func importedNote(name: String, html: String, fallbackTitle: String) -> ImportedNote {
        var blocks = convert(html: html)
        var title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { title = fallbackTitle }
        // 메모 앱은 본문 첫 줄이 곧 제목이라 본문에도 같은 줄이 들어 있다 — 중복을 없앤다.
        if let first = blocks.first, EditorDocument(content: [first]).derivedPlainText.trimmingCharacters(in: .whitespacesAndNewlines) == title {
            blocks.removeFirst()
        }
        if blocks.isEmpty { blocks = [EditorNode.paragraph("")] }
        let document = EditorDocument(content: blocks)
        return ImportedNote(title: title, document: document, plainText: document.derivedPlainText)
    }
}
