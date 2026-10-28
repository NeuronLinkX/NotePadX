import Foundation

/// Word(.docx)를 편집기 문서로 바꾼다. 문단·제목·글머리/번호 목록(중첩 포함)·표·굵게/기울임/밑줄/취소선·
/// 하이퍼링크·그림(PNG/JPEG/GIF)을 옮기고, 변경 추적의 삭제된 글은 제외한다. 머리글·각주·텍스트 상자·
/// 도형처럼 옮기지 못하는 것은 건너뛰며, 건너뛴 개수를 `skippedFeatures`로 알려 준다.
enum DocxImporter {
    enum DocxError: Error, Equatable {
        case notADocx
        case encrypted
        case unreadable(String)
    }

    struct Result {
        var note: ImportedNote
        var skippedFeatures: [String]
    }

    static let maxImageBytes = 8 * 1024 * 1024

    static func importDocument(from data: Data, fallbackTitle: String) throws -> Result {
        let zip: ZipArchiveReader
        do { zip = try ZipArchiveReader(data: data) } catch { throw DocxError.notADocx }
        guard zip.contains("word/document.xml") else {
            // 암호를 건 docx는 ZIP이 아니라 OLE 컨테이너다. 그 경우는 위에서 notADocx로 걸러진다.
            throw DocxError.notADocx
        }
        let documentXML: Data
        do { documentXML = try zip.read("word/document.xml") ?? Data() }
        catch ZipArchiveReader.ReadError.encrypted { throw DocxError.encrypted }
        catch { throw DocxError.unreadable("본문을 읽지 못했습니다") }

        let styles = (try? zip.read("word/styles.xml")).flatMap { $0 }.map(StyleTable.parse) ?? StyleTable()
        let numbering = (try? zip.read("word/numbering.xml")).flatMap { $0 }.map(NumberingTable.parse) ?? NumberingTable()
        let relationships = (try? zip.read("word/_rels/document.xml.rels")).flatMap { $0 }.map(Relationships.parse) ?? Relationships()

        let builder = BodyParser(styles: styles, numbering: numbering, relationships: relationships) { target in
            let path = target.hasPrefix("/") ? String(target.dropFirst()) : "word/" + target
            guard let entry = zip.entry(at: path), entry.uncompressedSize <= maxImageBytes else { return nil }
            return try? zip.read(entry)
        }
        let parser = XMLParser(data: documentXML)
        parser.delegate = builder
        parser.shouldProcessNamespaces = false
        guard parser.parse() || !builder.blocks.isEmpty else {
            throw DocxError.unreadable(parser.parserError?.localizedDescription ?? "XML 오류")
        }

        var blocks = convert(builder.blocks)
        var title = fallbackTitle
        if let firstTitle = builder.titleText { title = firstTitle }
        if blocks.isEmpty { blocks = [EditorNode.paragraph("")] }
        let document = EditorDocument(content: blocks)

        var skipped: [String] = []
        for (name, count) in builder.skipped.sorted(by: { $0.key < $1.key }) where count > 0 { skipped.append("\(name) \(count)개") }
        return Result(note: ImportedNote(title: title, document: document, plainText: document.derivedPlainText), skippedFeatures: skipped)
    }

    // MARK: - 중간 모델

    fileprivate struct ParagraphModel {
        var heading: Int?
        var isTitle = false
        var list: (ordered: Bool, level: Int)?
        var inline: [EditorNode] = []
        var images: [EditorNode] = []

        var isEmptyText: Bool { inline.allSatisfy { ($0.text ?? "").isEmpty && $0.type == "text" } }
    }

    fileprivate enum Block {
        case paragraph(ParagraphModel)
        case table([[[ParagraphModel]]])
    }

    // MARK: - 중간 모델 → 편집기 노드

    private static func convert(_ blocks: [BlockBox]) -> [EditorNode] {
        var result: [EditorNode] = []
        var index = 0
        while index < blocks.count {
            switch blocks[index].block {
            case .paragraph(let paragraph) where paragraph.list != nil:
                var run: [ParagraphModel] = []
                while index < blocks.count, case .paragraph(let p) = blocks[index].block, p.list != nil {
                    run.append(p)
                    index += 1
                }
                result.append(contentsOf: buildLists(run))
            case .paragraph(let paragraph):
                result.append(contentsOf: nodes(for: paragraph))
                index += 1
            case .table(let rows):
                result.append(tableNode(rows))
                index += 1
            }
        }
        return result
    }

    private static func nodes(for paragraph: ParagraphModel) -> [EditorNode] {
        var out: [EditorNode] = []
        if paragraph.isTitle { return paragraph.images }   // 제목 문단은 노트 제목으로 올렸다
        if let level = paragraph.heading {
            out.append(EditorNode(rawType: "heading", attrs: ["level": .number(Double(level))], content: paragraph.inline))
        } else {
            out.append(EditorNode(type: .paragraph, content: paragraph.inline))
        }
        out.append(contentsOf: paragraph.images)
        return out
    }

    private static func tableNode(_ rows: [[[ParagraphModel]]]) -> EditorNode {
        let columnCount = rows.map(\.count).max() ?? 1
        let tableRows = rows.enumerated().map { rowIndex, cells -> EditorNode in
            var cellNodes = cells.map { paragraphs -> EditorNode in
                var content = paragraphs.flatMap(nodes(for:))
                if content.isEmpty { content = [EditorNode(type: .paragraph)] }
                return EditorNode(rawType: rowIndex == 0 ? "tableHeader" : "tableCell", content: content)
            }
            while cellNodes.count < columnCount {
                cellNodes.append(EditorNode(rawType: rowIndex == 0 ? "tableHeader" : "tableCell", content: [EditorNode(type: .paragraph)]))
            }
            return EditorNode(rawType: "tableRow", content: cellNodes)
        }
        return EditorNode(rawType: "table", content: tableRows)
    }

    private static func buildLists(_ items: [ParagraphModel]) -> [EditorNode] {
        var cursor = 0

        func build(minLevel: Int) -> [EditorNode] {
            var result: [EditorNode] = []
            var current: [EditorNode] = []
            var currentOrdered: Bool?

            func flush() {
                guard let ordered = currentOrdered, !current.isEmpty else { return }
                result.append(EditorNode(rawType: ordered ? "orderedList" : "bulletList", content: current))
                current = []
            }

            while cursor < items.count {
                let item = items[cursor]
                guard let list = item.list, list.level >= minLevel else { break }
                if let existing = currentOrdered, existing != list.ordered { flush() }
                currentOrdered = list.ordered
                cursor += 1

                var content: [EditorNode] = [EditorNode(type: .paragraph, content: item.inline)]
                content.append(contentsOf: item.images)
                if cursor < items.count, let next = items[cursor].list, next.level > list.level {
                    content.append(contentsOf: build(minLevel: next.level))
                }
                current.append(EditorNode(type: .listItem, content: content))
            }
            flush()
            return result
        }

        var all: [EditorNode] = []
        while cursor < items.count { all.append(contentsOf: build(minLevel: items[cursor].list?.level ?? 0)) }
        return all
    }
}

// MARK: - 보조 표 (스타일·번호·관계)

private struct StyleTable {
    /// styleId → 이름(소문자)
    var names: [String: String] = [:]

    static func parse(_ data: Data) -> StyleTable {
        let collector = StyleCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        return StyleTable(names: collector.names)
    }

    func headingLevel(for styleID: String) -> Int? {
        let name = (names[styleID] ?? styleID).lowercased().replacingOccurrences(of: " ", with: "")
        if name.hasPrefix("heading"), let level = Int(name.dropFirst("heading".count)), (1...6).contains(level) { return level }
        return nil
    }

    func isTitle(_ styleID: String) -> Bool {
        (names[styleID] ?? styleID).lowercased() == "title"
    }
}

private final class StyleCollector: NSObject, XMLParserDelegate {
    var names: [String: String] = [:]
    private var currentID: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName == "w:style" { currentID = attributeDict["w:styleId"] }
        if elementName == "w:name", let id = currentID, let value = attributeDict["w:val"] { names[id] = value }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "w:style" { currentID = nil }
    }
}

private struct NumberingTable {
    /// numId → abstractNumId
    var numToAbstract: [String: String] = [:]
    /// "abstractNumId:ilvl" → numFmt
    var formats: [String: String] = [:]

    static func parse(_ data: Data) -> NumberingTable {
        let collector = NumberingCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        return NumberingTable(numToAbstract: collector.numToAbstract, formats: collector.formats)
    }

    func isOrdered(numID: String, level: Int) -> Bool {
        guard let abstract = numToAbstract[numID], let format = formats["\(abstract):\(level)"] else { return false }
        return format != "bullet" && format != "none"
    }
}

private final class NumberingCollector: NSObject, XMLParserDelegate {
    var numToAbstract: [String: String] = [:]
    var formats: [String: String] = [:]
    private var abstractID: String?
    private var level: String?
    private var numID: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        switch elementName {
        case "w:abstractNum": abstractID = attributeDict["w:abstractNumId"]
        case "w:lvl": level = attributeDict["w:ilvl"]
        case "w:numFmt":
            if let abstractID, let level, let value = attributeDict["w:val"] { formats["\(abstractID):\(level)"] = value }
        case "w:num": numID = attributeDict["w:numId"]
        case "w:abstractNumId":
            if let numID, let value = attributeDict["w:val"] { numToAbstract[numID] = value }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "w:abstractNum": abstractID = nil
        case "w:lvl": level = nil
        case "w:num": numID = nil
        default: break
        }
    }
}

private struct Relationships {
    var targets: [String: (target: String, external: Bool)] = [:]

    static func parse(_ data: Data) -> Relationships {
        let collector = RelationshipCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        return Relationships(targets: collector.targets)
    }
}

private final class RelationshipCollector: NSObject, XMLParserDelegate {
    var targets: [String: (target: String, external: Bool)] = [:]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        guard elementName == "Relationship", let id = attributeDict["Id"], let target = attributeDict["Target"] else { return }
        targets[id] = (target, attributeDict["TargetMode"] == "External")
    }
}

// MARK: - 본문 파서

/// 중간 결과를 담는 참조형 상자(열거형 연관값은 SAX 도중 수정하기 불편하다).
private final class BlockBox {
    var block: DocxImporter.Block
    init(_ block: DocxImporter.Block) { self.block = block }
}

private final class BodyParser: NSObject, XMLParserDelegate {
    private(set) var blocks: [BlockBox] = []
    private(set) var titleText: String?
    private(set) var skipped: [String: Int] = [:]

    private let styles: StyleTable
    private let numbering: NumberingTable
    private let relationships: Relationships
    private let loadMedia: (String) -> Data?

    // 문단 상태
    private var paragraph: DocxImporter.ParagraphModel?
    private var styleID = ""
    private var numID: String?
    private var ilvl = 0

    // 런 상태
    private var inRun = false
    private var inRunProperties = false
    private var runMarks = RunFormat()
    private var textBuffer = ""
    private var inText = false
    private var inDeletedText = false
    private var hyperlinkURL: String?
    private var imageRelID: String?
    private var inDrawing = 0
    private var inTextBox = 0

    // 표 상태 (중첩 표는 안쪽 표를 바깥 셀의 문단으로 풀어 넣는다)
    private var tableDepth = 0
    private var tableRows: [[[DocxImporter.ParagraphModel]]] = []
    private var currentRow: [[DocxImporter.ParagraphModel]] = []
    private var currentCell: [DocxImporter.ParagraphModel] = []

    struct RunFormat {
        var bold = false, italic = false, underline = false, strike = false
        var superscript = false, subscript_ = false
    }

    init(styles: StyleTable, numbering: NumberingTable, relationships: Relationships, loadMedia: @escaping (String) -> Data?) {
        self.styles = styles
        self.numbering = numbering
        self.relationships = relationships
        self.loadMedia = loadMedia
    }

    private func flag(_ attributes: [String: String]) -> Bool {
        guard let value = attributes["w:val"] else { return true }
        return !["0", "false", "off", "none"].contains(value.lowercased())
    }

    private func skip(_ name: String) { skipped[name, default: 0] += 1 }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        switch elementName {
        case "w:tbl":
            tableDepth += 1
            if tableDepth == 1 { tableRows = [] }
        case "w:tr":
            if tableDepth == 1 { currentRow = [] }
        case "w:tc":
            if tableDepth == 1 { currentCell = [] }

        case "w:p":
            paragraph = DocxImporter.ParagraphModel()
            styleID = ""
            numID = nil
            ilvl = 0
        case "w:pStyle": styleID = attributeDict["w:val"] ?? ""
        case "w:numId": numID = attributeDict["w:val"]
        case "w:ilvl": ilvl = Int(attributeDict["w:val"] ?? "0") ?? 0

        case "w:hyperlink":
            if let id = attributeDict["r:id"], let rel = relationships.targets[id], rel.external { hyperlinkURL = rel.target }
            else if let anchor = attributeDict["w:anchor"] { _ = anchor; hyperlinkURL = nil }
        case "w:r":
            inRun = true
            runMarks = RunFormat()
            imageRelID = nil
        case "w:rPr": if inRun { inRunProperties = true }
        case "w:b": if inRunProperties { runMarks.bold = flag(attributeDict) }
        case "w:i": if inRunProperties { runMarks.italic = flag(attributeDict) }
        case "w:u": if inRunProperties { runMarks.underline = flag(attributeDict) }
        case "w:strike", "w:dstrike": if inRunProperties { runMarks.strike = flag(attributeDict) }
        case "w:vertAlign":
            if inRunProperties {
                runMarks.superscript = attributeDict["w:val"] == "superscript"
                runMarks.subscript_ = attributeDict["w:val"] == "subscript"
            }
        case "w:t":
            if inRun, inTextBox == 0 { inText = true; textBuffer = "" }
        case "w:delText": inDeletedText = true
        case "w:tab": if inRun, !inRunProperties { appendText("\t") }
        case "w:br", "w:cr":
            if inRun, attributeDict["w:type"] != "page", attributeDict["w:type"] != "column" { flushText(); appendNode(EditorNode(rawType: "hardBreak")) }

        case "w:drawing", "w:pict":
            inDrawing += 1
        case "a:blip":
            if inDrawing > 0, let id = attributeDict["r:embed"] { imageRelID = id }
        case "w:txbxContent":
            inTextBox += 1
            skip("텍스트 상자")
        case "w:footnoteReference", "w:endnoteReference":
            skip("각주")
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { textBuffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "w:t":
            if inText { appendText(textBuffer); textBuffer = ""; inText = false }
        case "w:delText": inDeletedText = false
        case "w:rPr": inRunProperties = false
        case "w:drawing", "w:pict":
            inDrawing = max(0, inDrawing - 1)
            if inDrawing == 0 { attachPendingImage() }
        case "w:r":
            flushText()
            inRun = false
            inRunProperties = false
        case "w:hyperlink": hyperlinkURL = nil
        case "w:txbxContent": inTextBox = max(0, inTextBox - 1)
        case "w:p":
            finishParagraph()
        case "w:tc":
            if tableDepth == 1 { currentRow.append(currentCell); currentCell = [] }
        case "w:tr":
            if tableDepth == 1 { tableRows.append(currentRow); currentRow = [] }
        case "w:tbl":
            if tableDepth == 1, !tableRows.isEmpty { blocks.append(BlockBox(.table(tableRows))); tableRows = [] }
            tableDepth = max(0, tableDepth - 1)
        default: break
        }
    }

    // MARK: 런 조립

    private var pendingText = ""

    private func appendText(_ text: String) {
        guard inTextBox == 0, !inDeletedText else { return }
        pendingText += text
    }

    private func flushText() {
        guard !pendingText.isEmpty else { return }
        var marks: [EditorMark] = []
        if runMarks.bold { marks.append(EditorMark(type: .bold)) }
        if runMarks.italic { marks.append(EditorMark(type: .italic)) }
        if runMarks.underline { marks.append(EditorMark(type: .underline)) }
        if runMarks.strike { marks.append(EditorMark(type: .strike)) }
        if runMarks.superscript { marks.append(EditorMark(type: .superscript)) }
        if runMarks.subscript_ { marks.append(EditorMark(type: .subscript_)) }
        if let url = hyperlinkURL { marks.append(EditorMark(type: .link, attrs: ["href": .string(url)])) }
        appendNode(.textNode(pendingText, marks: marks.isEmpty ? nil : marks))
        pendingText = ""
    }

    private func appendNode(_ node: EditorNode) {
        guard inTextBox == 0 else { return }
        paragraph?.inline.append(node)
    }

    private func attachPendingImage() {
        guard let id = imageRelID, inTextBox == 0 else { return }
        imageRelID = nil
        guard let rel = relationships.targets[id], !rel.external, let bytes = loadMedia(rel.target) else {
            skip("그림")
            return
        }
        let mime: String?
        let lower = rel.target.lowercased()
        if lower.hasSuffix(".png") { mime = "image/png" }
        else if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { mime = "image/jpeg" }
        else if lower.hasSuffix(".gif") { mime = "image/gif" }
        else { mime = nil }
        guard let mime else { skip("지원하지 않는 형식의 그림"); return }
        let node = EditorNode(rawType: "image", attrs: ["src": .string("data:\(mime);base64,\(bytes.base64EncodedString())")])
        paragraph?.images.append(node)
    }

    // MARK: 문단 마감

    private func finishParagraph() {
        guard var finished = paragraph else { return }
        paragraph = nil
        flushText()
        finished = paragraphWithStyle(finished)

        // 같은 문단 안의 연속된 글자 노드는 합친다.
        finished.inline = Self.mergeAdjacentText(finished.inline)

        if tableDepth > 0 {
            // 표 셀 안(중첩 표 포함)의 문단은 현재 셀에 쌓는다. 중첩 표 안의 문단도 바깥 셀로 올라간다.
            if finished.isTitle { finished.isTitle = false; finished.heading = 1 }
            currentCell.append(finished)
            return
        }
        if finished.isTitle {
            // 첫 번째 "제목" 문단만 메모 제목이 된다. 그 밖의 제목 문단(비었거나 두 번째 이후)은 1단계 제목으로 남긴다.
            let text = finished.inline.compactMap(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            if titleText == nil, !text.isEmpty {
                titleText = text
            } else {
                finished.isTitle = false
                finished.heading = 1
            }
        }
        // 완전히 빈 문단도 문서의 여백 구조이므로 유지한다.
        blocks.append(BlockBox(.paragraph(finished)))
    }

    private func paragraphWithStyle(_ source: DocxImporter.ParagraphModel) -> DocxImporter.ParagraphModel {
        var p = source
        if !styleID.isEmpty {
            if styles.isTitle(styleID) { p.isTitle = true }
            else { p.heading = styles.headingLevel(for: styleID) }
        }
        if let numID, numID != "0", p.heading == nil {
            p.list = (ordered: numbering.isOrdered(numID: numID, level: ilvl), level: ilvl)
        }
        return p
    }

    private static func mergeAdjacentText(_ nodes: [EditorNode]) -> [EditorNode] {
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
}
