import Foundation

/// EditorDocument를 실제 Office Open XML(WordprocessingML) 패키지로 만든다.
/// 확장자만 바꾸는 방식이 아니라 스펙 15절이 요구하는 최소 파트 구성
/// ([Content_Types].xml, _rels/.rels, word/document.xml, word/styles.xml, word/numbering.xml,
/// word/_rels/document.xml.rels, docProps/core.xml, docProps/app.xml)을 실제로 만들어 ZIP으로 묶는다.
///
/// 목록(bulletList/orderedList)은 진짜 OOXML numbering.xml(자동 번호 매기기)로 나간다 — Word의
/// "글머리 기호/번호 매기기" 리본 메뉴가 이 목록을 인식하고, 항목을 재정렬하면 번호가 자동으로
/// 갱신된다. 체크리스트(taskList)만은 예외로 "☑/☐" 접두어 텍스트로 남긴다: 실제 클릭 가능한
/// 확인란을 만들려면 w:sdt 콘텐츠 컨트롤이 필요한데, 완료 여부를 텍스트로만 보여줘도 충분하다고
/// 판단해 범위를 좁혔다.
enum DocxExporter {
    static func export(title: String, document: EditorDocument, note: Note?, options: ExportOptions) throws -> Data {
        let builder = DocxBodyBuilder(options: options)
        var bodyXML = ""

        if options.includeTitle, !title.isEmpty {
            bodyXML += builder.titleParagraph(title)
        }
        if options.includeDates, let note {
            bodyXML += builder.metadataParagraph(
                "생성: \(DateFormatting.export.string(from: note.createdAt))  ·  수정: \(DateFormatting.export.string(from: note.updatedAt))"
            )
        }
        if !options.author.isEmpty {
            bodyXML += builder.metadataParagraph("작성자: \(options.author)")
        }

        for node in document.content {
            bodyXML += builder.renderBlock(node)
        }
        bodyXML += builder.sectionProperties()

        var zip = ZipArchiveWriter()
        zip.addFile(path: "[Content_Types].xml", data: Data(Templates.contentTypes.utf8))
        zip.addFile(path: "_rels/.rels", data: Data(Templates.rootRels.utf8))
        zip.addFile(path: "docProps/core.xml", data: Data(Templates.coreProperties(title: title, author: options.author).utf8))
        zip.addFile(path: "docProps/app.xml", data: Data(Templates.appProperties.utf8))
        zip.addFile(path: "word/styles.xml", data: Data(Templates.styles.utf8))
        zip.addFile(path: "word/numbering.xml", data: Data(builder.numberingXML().utf8))
        zip.addFile(path: "word/_rels/document.xml.rels", data: Data(builder.documentRels().utf8))
        zip.addFile(path: "word/document.xml", data: Data(Templates.document(body: bodyXML).utf8))

        return zip.finalize()
    }
}

/// document.xml 본문(w:body 내부)을 생성하면서, 하이퍼링크처럼 관계(rels) 파일에도
/// 등록해야 하는 항목을 함께 모은다.
private final class DocxBodyBuilder {
    private enum ListKind: Equatable { case bullet, ordered }
    private static let bulletAbstractNumId = 0
    private static let orderedAbstractNumId = 1
    private static let maxListLevel = 8

    private let options: ExportOptions
    private var relationships: [(id: String, target: String)] = []
    private var nextRelIndex = 1
    private var numberingEntries: [(numId: Int, abstractNumId: Int)] = []
    private var numIdKinds: [Int: ListKind] = [:]
    private var nextNumId = 1

    init(options: ExportOptions) {
        self.options = options
    }

    /// bulletList/orderedList를 새로 만날 때마다 독립된 numId를 하나 발급한다 — 같은 종류의
    /// 목록이 문서에 여러 개 있어도 서로 다른 목록은 번호가 1부터 다시 시작해야 하기 때문이다.
    private func registerList(kind: ListKind) -> Int {
        let numId = nextNumId
        nextNumId += 1
        let abstractNumId = kind == .bullet ? Self.bulletAbstractNumId : Self.orderedAbstractNumId
        numberingEntries.append((numId: numId, abstractNumId: abstractNumId))
        numIdKinds[numId] = kind
        return numId
    }

    func numberingXML() -> String {
        Templates.numbering(entries: numberingEntries)
    }

    func titleParagraph(_ text: String) -> String {
        """
        <w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr><w:r><w:t xml:space="preserve">\(XML.escape(text))</w:t></w:r></w:p>
        """
    }

    func metadataParagraph(_ text: String) -> String {
        """
        <w:p><w:pPr><w:pStyle w:val="Subtitle"/></w:pPr><w:r><w:t xml:space="preserve">\(XML.escape(text))</w:t></w:r></w:p>
        """
    }

    func sectionProperties() -> String {
        let size = options.pageSize.pointSize
        let margin = Int(options.margins.points * 20)
        let widthTwips = Int(size.width * 20)
        let heightTwips = Int(size.height * 20)
        var footer = ""
        if options.includeHeaderFooter {
            footer = """
            <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:t xml:space="preserve">NotepadX</w:t></w:r></w:p>
            """
        }
        return """
        \(footer)<w:sectPr><w:pgSz w:w="\(widthTwips)" w:h="\(heightTwips)"/><w:pgMar w:top="\(margin)" w:right="\(margin)" w:bottom="\(margin)" w:left="\(margin)"/></w:sectPr>
        """
    }

    /// usable width는 표 열 너비를 균등 분배할 때 쓴다.
    private var usableWidthTwips: Int {
        Int((options.pageSize.pointSize.width - options.margins.points * 2) * 20)
    }

    func renderBlock(_ node: EditorNode, listMarker: String? = nil) -> String {
        switch node.type {
        case "paragraph":
            return paragraph(runs: renderInline(node.content ?? []), listMarker: listMarker)

        case "heading":
            let level = intAttr(node, "level") ?? 1
            let style = "Heading\(max(1, min(level, 6)))"
            let markerRun = listMarker.map { "<w:r><w:t xml:space=\"preserve\">\(XML.escape($0))</w:t></w:r>" } ?? ""
            return """
            <w:p><w:pPr><w:pStyle w:val="\(style)"/></w:pPr>\(markerRun)\(renderInline(node.content ?? []))</w:p>
            """

        case "bulletList":
            let numId = registerList(kind: .bullet)
            return (node.content ?? []).map { renderNumberedListItem($0, numId: numId, level: 0) }.joined()

        case "orderedList":
            let numId = registerList(kind: .ordered)
            return (node.content ?? []).map { renderNumberedListItem($0, numId: numId, level: 0) }.joined()

        case "taskList":
            return (node.content ?? []).map { item -> String in
                let checked = boolAttr(item, "checked") ?? false
                return renderListItem(item, marker: checked ? "☑  " : "☐  ")
            }.joined()

        case "blockquote":
            let inner = (node.content ?? []).map { renderBlock($0) }.joined()
            return inner.replacingOccurrences(of: "<w:pPr>", with: "<w:pPr><w:pStyle w:val=\"Quote\"/>")

        case "codeBlock":
            return codeBlockParagraph(node)

        case "horizontalRule":
            return """
            <w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="999999"/></w:pBdr></w:pPr></w:p>
            """

        case "table":
            return renderTable(node)

        case "details":
            let summary = (node.content ?? []).first { $0.type == "detailsSummary" }
            let content = (node.content ?? []).first { $0.type == "detailsContent" }
            var xml = paragraph(runs: "▸ " + renderInline(summary?.content ?? []), listMarker: nil)
            xml += (content?.content ?? []).map { renderBlock($0) }.joined()
            return xml

        case "image":
            let alt = stringAttr(node, "alt") ?? "이미지"
            return paragraph(runs: "[이미지: \(XML.escape(alt))]", listMarker: nil)

        case "fileAttachment":
            let fileName = stringAttr(node, "fileName") ?? "첨부파일"
            return paragraph(runs: "📎 \(XML.escape(fileName))", listMarker: nil)

        default:
            if let text = node.text {
                return paragraph(runs: XML.escape(text), listMarker: nil)
            }
            return (node.content ?? []).map { renderBlock($0) }.joined()
        }
    }

    /// taskList 전용 — 체크박스는 텍스트 접두어로 남긴다(클래스 상단 설명 참고).
    private func renderListItem(_ item: EditorNode, marker: String) -> String {
        let paragraphs = (item.content ?? [])
        guard let first = paragraphs.first else { return paragraph(runs: XML.escape(marker), listMarker: nil) }
        var xml = renderBlock(first, listMarker: marker)
        for extra in paragraphs.dropFirst() {
            xml += renderBlock(extra, listMarker: "    ")
        }
        return xml
    }

    /// bulletList/orderedList 전용 — 실제 w:numPr(numId/ilvl)을 붙여서 Word가 진짜 목록으로
    /// 인식하게 한다. 같은 종류가 중첩되면(리스트 안에 같은 종류 리스트) numId를 그대로 두고
    /// level만 늘리고, 다른 종류가 중첩되면 새 numId를 level 0부터 새로 발급한다.
    private func renderNumberedListItem(_ item: EditorNode, numId: Int, level: Int) -> String {
        let children = item.content ?? []
        let clampedLevel = min(level, Self.maxListLevel)
        guard let first = children.first else {
            return injectNumbering(into: paragraph(runs: "", listMarker: nil), numId: numId, level: clampedLevel)
        }
        var xml = injectNumbering(into: renderBlock(first), numId: numId, level: clampedLevel)
        for extra in children.dropFirst() {
            switch extra.type {
            case "bulletList":
                let nestedNumId = numIdKinds[numId] == .bullet ? numId : registerList(kind: .bullet)
                xml += (extra.content ?? []).map { renderNumberedListItem($0, numId: nestedNumId, level: clampedLevel + 1) }.joined()
            case "orderedList":
                let nestedNumId = numIdKinds[numId] == .ordered ? numId : registerList(kind: .ordered)
                xml += (extra.content ?? []).map { renderNumberedListItem($0, numId: nestedNumId, level: clampedLevel + 1) }.joined()
            default:
                xml += renderBlock(extra)
            }
        }
        return xml
    }

    /// 이미 렌더된 `<w:p>...</w:p>` XML의 첫 <w:pPr>(없으면 새로 만들어서) 안에 numPr을 끼워 넣는다.
    /// renderBlock을 그대로 재사용하면서 목록 서식만 덧붙이기 위한 후처리 방식이다.
    private func injectNumbering(into paragraphXML: String, numId: Int, level: Int) -> String {
        let numPr = "<w:numPr><w:ilvl w:val=\"\(level)\"/><w:numId w:val=\"\(numId)\"/></w:numPr>"
        if let range = paragraphXML.range(of: "<w:pPr>") {
            var result = paragraphXML
            result.replaceSubrange(range, with: "<w:pPr>\(numPr)")
            return result
        } else if let range = paragraphXML.range(of: "<w:p>") {
            var result = paragraphXML
            result.replaceSubrange(range, with: "<w:p><w:pPr>\(numPr)</w:pPr>")
            return result
        }
        return paragraphXML
    }

    private func paragraph(runs: String, listMarker: String?) -> String {
        let markerRun = listMarker.map { "<w:r><w:t xml:space=\"preserve\">\(XML.escape($0))</w:t></w:r>" } ?? ""
        return "<w:p>\(markerRun)\(runs)</w:p>"
    }

    private func codeBlockParagraph(_ node: EditorNode) -> String {
        let code = (node.content ?? []).map { $0.text ?? "" }.joined()
        var codeLines = code.components(separatedBy: "\n")
        if options.codeBlockLineNumbers {
            let width = String(codeLines.count).count
            codeLines = codeLines.enumerated().map { i, line in String(format: "%\(width)d| %@", i + 1, line) }
        }
        let fontXML = "<w:rFonts w:ascii=\"\(options.codeFont)\" w:hAnsi=\"\(options.codeFont)\"/>"
        let runs = codeLines.enumerated().map { index, line -> String in
            let breakTag = index == 0 ? "" : "<w:br/>"
            return "<w:r><w:rPr>\(fontXML)<w:sz w:val=\"18\"/></w:rPr>\(breakTag)<w:t xml:space=\"preserve\">\(XML.escape(line))</w:t></w:r>"
        }.joined()
        return """
        <w:p><w:pPr><w:shd w:val="clear" w:color="auto" w:fill="F5F5F5"/></w:pPr>\(runs)</w:p>
        """
    }

    private func renderTable(_ node: EditorNode) -> String {
        let rows = node.content ?? []
        guard !rows.isEmpty else { return "" }
        let columnCount = max(1, (rows.first?.content ?? []).count)
        let columnWidth = usableWidthTwips / columnCount

        let borderXML = options.showTableBorders
            ? """
              <w:tblBorders>
                <w:top w:val="single" w:sz="4" w:color="999999"/>
                <w:left w:val="single" w:sz="4" w:color="999999"/>
                <w:bottom w:val="single" w:sz="4" w:color="999999"/>
                <w:right w:val="single" w:sz="4" w:color="999999"/>
                <w:insideH w:val="single" w:sz="4" w:color="999999"/>
                <w:insideV w:val="single" w:sz="4" w:color="999999"/>
              </w:tblBorders>
              """
            : ""

        let grid = (0..<columnCount).map { _ in "<w:gridCol w:w=\"\(columnWidth)\"/>" }.joined()

        let rowsXML = rows.map { row -> String in
            let cells = (row.content ?? []).map { cell -> String in
                let isHeader = cell.type == "tableHeader"
                let cellParagraphs = (cell.content ?? []).map { renderBlock($0) }.joined()
                let shading = isHeader ? "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"EFEFEF\"/>" : ""
                return """
                <w:tc><w:tcPr><w:tcW w:w="\(columnWidth)" w:type="dxa"/>\(shading)</w:tcPr>\(cellParagraphs.isEmpty ? "<w:p/>" : cellParagraphs)</w:tc>
                """
            }.joined()
            return "<w:tr>\(cells)</w:tr>"
        }.joined()

        return """
        <w:tbl>
          <w:tblPr><w:tblW w:w="\(usableWidthTwips)" w:type="dxa"/>\(borderXML)</w:tblPr>
          <w:tblGrid>\(grid)</w:tblGrid>
          \(rowsXML)
        </w:tbl>
        <w:p/>
        """
    }

    private func renderInline(_ nodes: [EditorNode]) -> String {
        nodes.map { node -> String in
            if node.type == "hardBreak" { return "<w:r><w:br/></w:r>" }
            guard let text = node.text else { return renderInline(node.content ?? []) }

            let marks = node.marks ?? []
            let markTypes = Set(marks.map(\.type))
            var rPr = ""
            if markTypes.contains("bold") { rPr += "<w:b/>" }
            if markTypes.contains("italic") { rPr += "<w:i/>" }
            if markTypes.contains("underline") { rPr += "<w:u w:val=\"single\"/>" }
            if markTypes.contains("strike") { rPr += "<w:strike/>" }
            if markTypes.contains("code") { rPr += "<w:rFonts w:ascii=\"\(options.codeFont)\" w:hAnsi=\"\(options.codeFont)\"/>" }

            if let textStyle = marks.first(where: { $0.type == "textStyle" }) {
                if case .string(let hex)? = textStyle.attrs?["color"] {
                    rPr += "<w:color w:val=\"\(hexWithoutHash(hex))\"/>"
                }
                if case .string(let fontSizeCSS)? = textStyle.attrs?["fontSize"], let halfPoints = halfPoints(fromCSS: fontSizeCSS) {
                    rPr += "<w:sz w:val=\"\(halfPoints)\"/><w:szCs w:val=\"\(halfPoints)\"/>"
                }
                if case .string(let family)? = textStyle.attrs?["fontFamily"] {
                    rPr += "<w:rFonts w:ascii=\"\(family)\" w:hAnsi=\"\(family)\"/>"
                }
            }
            if let highlight = marks.first(where: { $0.type == "highlight" }), case .string(let hex)? = highlight.attrs?["color"] {
                rPr += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(hexWithoutHash(hex))\"/>"
            }

            let runXML = "<w:r>\(rPr.isEmpty ? "" : "<w:rPr>\(rPr)</w:rPr>")<w:t xml:space=\"preserve\">\(XML.escape(text))</w:t></w:r>"

            if let link = marks.first(where: { $0.type == "link" }), case .string(let href)? = link.attrs?["href"] {
                let relID = registerRelationship(target: href)
                return "<w:hyperlink r:id=\"\(relID)\"><w:r><w:rPr><w:rStyle w:val=\"Hyperlink\"/>\(rPr)</w:rPr><w:t xml:space=\"preserve\">\(XML.escape(text))</w:t></w:r></w:hyperlink>"
            }
            return runXML
        }.joined()
    }

    private func registerRelationship(target: String) -> String {
        let id = "rId\(100 + nextRelIndex)"
        nextRelIndex += 1
        relationships.append((id: id, target: target))
        return id
    }

    func documentRels() -> String {
        let styleRel = """
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
        """
        let hyperlinkRels = relationships.map {
            """
            <Relationship Id="\($0.id)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="\(XML.escape($0.target))" TargetMode="External"/>
            """
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        \(styleRel)
        \(hyperlinkRels)
        </Relationships>
        """
    }

    private func hexWithoutHash(_ hex: String) -> String {
        hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    }

    private func halfPoints(fromCSS css: String) -> Int? {
        let digits = css.prefix { $0.isNumber || $0 == "." }
        guard let px = Double(digits) else { return nil }
        let pt = px * 0.75
        return max(2, Int((pt * 2).rounded()))
    }

    private func stringAttr(_ node: EditorNode, _ key: String) -> String? {
        if case .string(let value)? = node.attrs?[key] { return value }
        return nil
    }

    private func intAttr(_ node: EditorNode, _ key: String) -> Int? {
        if case .number(let value)? = node.attrs?[key] { return Int(value) }
        return nil
    }

    private func boolAttr(_ node: EditorNode, _ key: String) -> Bool? {
        if case .bool(let value)? = node.attrs?[key] { return value }
        return nil
    }
}

private enum XML {
    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
