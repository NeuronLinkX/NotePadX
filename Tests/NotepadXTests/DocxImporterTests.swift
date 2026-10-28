import XCTest
@testable import NotepadX

final class DocxImporterTests: XCTestCase {
    private let ns = #"xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main""#

    private func documentXML(_ body: String) -> String {
        #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document \#(ns)><w:body>\#(body)</w:body></w:document>"#
    }

    private func stored(files: [String: Data]) -> Data {
        var writer = ZipArchiveWriter()
        for (path, data) in files.sorted(by: { $0.key < $1.key }) { writer.addFile(path: path, data: data) }
        return writer.finalize()
    }

    private let stylesXML = #"""
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/></w:style>
        <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/></w:style>
        <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/></w:style>
        <w:style w:type="paragraph" w:styleId="Custom9"><w:name w:val="heading 3"/></w:style>
        </w:styles>
        """#

    private let numberingXML = #"""
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/></w:lvl><w:lvl w:ilvl="1"><w:numFmt w:val="bullet"/></w:lvl></w:abstractNum>
        <w:abstractNum w:abstractNumId="1"><w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/></w:lvl></w:abstractNum>
        <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
        <w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
        </w:numbering>
        """#

    private func makeDocx(body: String, extra: [String: Data] = [:]) -> Data {
        var files: [String: Data] = [
            "word/document.xml": Data(documentXML(body).utf8),
            "word/styles.xml": Data(stylesXML.utf8),
            "word/numbering.xml": Data(numberingXML.utf8),
            "[Content_Types].xml": Data("<Types/>".utf8),
        ]
        for (k, v) in extra { files[k] = v }
        return stored(files: files)
    }

    private func importBody(_ body: String, extra: [String: Data] = [:]) throws -> DocxImporter.Result {
        try DocxImporter.importDocument(from: makeDocx(body: body, extra: extra), fallbackTitle: "파일")
    }

    private func p(_ text: String, style: String? = nil, props: String = "", numId: Int? = nil, ilvl: Int = 0) -> String {
        var pPr = ""
        if let style { pPr += #"<w:pStyle w:val="\#(style)"/>"# }
        if let numId { pPr += #"<w:numPr><w:ilvl w:val="\#(ilvl)"/><w:numId w:val="\#(numId)"/></w:numPr>"# }
        let rPr = props.isEmpty ? "" : "<w:rPr>\(props)</w:rPr>"
        return "<w:p><w:pPr>\(pPr)</w:pPr><w:r>\(rPr)<w:t xml:space=\"preserve\">\(text)</w:t></w:r></w:p>"
    }

    func testParagraphsHeadingsAndTitle() throws {
        let result = try importBody(p("보고서", style: "Title") + p("개요", style: "Heading1") + p("본문 한 줄") + p("세부", style: "Custom9"))
        XCTAssertEqual(result.note.title, "보고서")
        XCTAssertEqual(result.note.document.content.map(\.type), ["heading", "paragraph", "heading"])
        XCTAssertEqual(result.note.document.content[0].attrs?["level"], .number(1))
        XCTAssertEqual(result.note.document.content[2].attrs?["level"], .number(3))
        XCTAssertEqual(result.note.plainText, "개요\n본문 한 줄\n세부")
    }

    func testFallbackTitleWhenNoTitleStyle() throws {
        let result = try importBody(p("그냥 문단"))
        XCTAssertEqual(result.note.title, "파일")
    }

    func testSecondTitleParagraphIsKeptAsHeading() throws {
        let result = try importBody(p("첫째", style: "Title") + p("둘째", style: "Title"))
        XCTAssertEqual(result.note.title, "첫째")
        XCTAssertEqual(result.note.plainText, "둘째")
        XCTAssertEqual(result.note.document.content.first?.type, "heading")
    }

    func testRunFormattingAndMerging() throws {
        let body = #"<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>굵</w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>게</w:t></w:r><w:r><w:rPr><w:i/><w:u w:val="single"/><w:strike/></w:rPr><w:t> 나머지</w:t></w:r><w:r><w:rPr><w:b w:val="0"/></w:rPr><w:t> 평범</w:t></w:r></w:p>"#
        let nodes = try importBody(body).note.document.content[0].content ?? []
        XCTAssertEqual(nodes.count, 3, "같은 서식의 연속된 런은 하나로 합쳐진다")
        XCTAssertEqual(nodes[0].text, "굵게")
        XCTAssertEqual(nodes[0].marks?.map(\.type), ["bold"])
        XCTAssertEqual(Set(nodes[1].marks?.map(\.type) ?? []), ["italic", "underline", "strike"])
        XCTAssertNil(nodes[2].marks)
    }

    func testBulletOrderedAndNestedLists() throws {
        let body = p("a", numId: 1) + p("a-1", numId: 1, ilvl: 1) + p("b", numId: 1) + p("끝난 뒤 문단") + p("첫째", numId: 2) + p("둘째", numId: 2)
        let content = try importBody(body).note.document.content
        XCTAssertEqual(content.map(\.type), ["bulletList", "paragraph", "orderedList"])
        let bullet = content[0]
        XCTAssertEqual(bullet.content?.count, 2)
        XCTAssertEqual(bullet.content?[0].content?.map(\.type), ["paragraph", "bulletList"])
        XCTAssertEqual(content[2].content?.count, 2)
    }

    func testTableBecomesHeaderPlusCells() throws {
        let cell = { (t: String) in "<w:tc>\(self.p(t))</w:tc>" }
        let table = "<w:tbl><w:tr>\(cell("이름"))\(cell("값"))</w:tr><w:tr>\(cell("a"))\(cell("1"))</w:tr></w:tbl>"
        let content = try importBody(p("앞") + table + p("뒤")).note.document.content
        XCTAssertEqual(content.map(\.type), ["paragraph", "table", "paragraph"])
        let rows = content[1].content ?? []
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].content?.map(\.type), ["tableHeader", "tableHeader"])
        XCTAssertEqual(rows[1].content?.map(\.type), ["tableCell", "tableCell"])
    }

    func testRaggedTableRowsArePadded() throws {
        let cell = { (t: String) in "<w:tc>\(self.p(t))</w:tc>" }
        let table = "<w:tbl><w:tr>\(cell("a"))\(cell("b"))</w:tr><w:tr>\(cell("c"))</w:tr></w:tbl>"
        let rows = try importBody(table).note.document.content[0].content ?? []
        XCTAssertEqual(rows[1].content?.count, 2)
    }

    func testTrackedDeletionsAreDropped() throws {
        let body = #"<w:p><w:r><w:t>남는 글</w:t></w:r><w:del><w:r><w:delText>지워진 글</w:delText></w:r></w:del></w:p>"#
        XCTAssertEqual(try importBody(body).note.plainText, "남는 글")
    }

    func testTabAndLineBreak() throws {
        let body = #"<w:p><w:r><w:t>가</w:t><w:tab/><w:t>나</w:t><w:br/><w:t>다</w:t></w:r></w:p>"#
        let nodes = try importBody(body).note.document.content[0].content ?? []
        XCTAssertEqual(nodes.map(\.type), ["text", "hardBreak", "text"])
        XCTAssertEqual(nodes[0].text, "가\t나")
    }

    func testExternalHyperlinkBecomesLinkMark() throws {
        let rels = #"<Relationships xmlns="x"><Relationship Id="rId5" Type="hyperlink" Target="https://example.com/x" TargetMode="External"/></Relationships>"#
        let body = #"<w:p><w:hyperlink r:id="rId5"><w:r><w:t>사이트</w:t></w:r></w:hyperlink></w:p>"#
        let nodes = try importBody(body, extra: ["word/_rels/document.xml.rels": Data(rels.utf8)]).note.document.content[0].content ?? []
        XCTAssertEqual(nodes.first?.marks?.first?.type, "link")
        XCTAssertEqual(nodes.first?.marks?.first?.attrs?["href"], .string("https://example.com/x"))
    }

    func testEmbeddedImageBecomesDataURI() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])
        let rels = #"<Relationships xmlns="x"><Relationship Id="rId9" Type="image" Target="media/image1.png"/></Relationships>"#
        let body = #"<w:p><w:r><w:drawing><a:graphic><a:graphicData><a:blip r:embed="rId9"/></a:graphicData></a:graphic></w:drawing></w:r></w:p>"#
        let result = try importBody(body, extra: ["word/_rels/document.xml.rels": Data(rels.utf8), "word/media/image1.png": png])
        let image = result.note.document.content.first { $0.type == "image" }
        XCTAssertEqual(image?.attrs?["src"], .string("data:image/png;base64,\(png.base64EncodedString())"))
        XCTAssertTrue(result.skippedFeatures.isEmpty)
    }

    func testMissingImageIsReportedNotFatal() throws {
        let rels = #"<Relationships xmlns="x"><Relationship Id="rId9" Type="image" Target="media/none.png"/></Relationships>"#
        let body = p("앞") + #"<w:p><w:r><w:drawing><a:blip r:embed="rId9"/></w:drawing></w:r></w:p>"#
        let result = try importBody(body, extra: ["word/_rels/document.xml.rels": Data(rels.utf8)])
        XCTAssertTrue(result.skippedFeatures.contains { $0.hasPrefix("그림") })
        XCTAssertTrue(result.note.plainText.contains("앞"))
    }

    func testTextBoxContentIsSkippedAndReported() throws {
        let body = p("본문") + #"<w:p><w:r><w:pict><w:txbxContent><w:p><w:r><w:t>상자 안 글</w:t></w:r></w:p></w:txbxContent></w:pict></w:r></w:p>"#
        let result = try importBody(body)
        XCTAssertFalse(result.note.plainText.contains("상자 안 글"))
        XCTAssertTrue(result.skippedFeatures.contains { $0.hasPrefix("텍스트 상자") })
    }

    func testNotAZipAndMissingDocumentThrow() {
        XCTAssertThrowsError(try DocxImporter.importDocument(from: Data("hello".utf8), fallbackTitle: "x")) {
            XCTAssertEqual($0 as? DocxImporter.DocxError, .notADocx)
        }
        let zipWithoutDoc = stored(files: ["a.txt": Data("x".utf8)])
        XCTAssertThrowsError(try DocxImporter.importDocument(from: zipWithoutDoc, fallbackTitle: "x")) {
            XCTAssertEqual($0 as? DocxImporter.DocxError, .notADocx)
        }
    }

    func testCorruptedEntryIsDetectedByCRC() throws {
        var data = makeDocx(body: p("내용"))
        // 본문 XML 안의 글자 하나를 바꾼다(저장 방식 항목이라 그대로 들어 있다).
        let needle = Data("내용".utf8)
        let range = try XCTUnwrap(data.range(of: needle))
        data[range.lowerBound] ^= 0x01
        XCTAssertThrowsError(try DocxImporter.importDocument(from: data, fallbackTitle: "x"))
    }

    /// 실제 Word 파일처럼 deflate로 압축된 ZIP — 시스템 `zip`으로 만들어 리더가 raw deflate를 푸는지 본다.
    func testDeflatedArchiveFromSystemZip() throws {
        let zipTool = URL(fileURLWithPath: "/usr/bin/zip")
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: zipTool.path), "zip 없음")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("docx-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("word"), withIntermediateDirectories: true)
        // 압축이 실제로 일어나도록 반복되는 긴 본문을 쓴다.
        let long = (1...200).map { p("반복되는 문장 \($0) — 압축이 잘 되는 내용입니다.") }.joined()
        try Data(documentXML(p("보고서", style: "Title") + long).utf8).write(to: dir.appendingPathComponent("word/document.xml"))
        try Data(stylesXML.utf8).write(to: dir.appendingPathComponent("word/styles.xml"))

        let out = dir.appendingPathComponent("test.docx")
        let process = Process()
        process.executableURL = zipTool
        process.currentDirectoryURL = dir
        process.arguments = ["-q", "-r", "-X", "test.docx", "word"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let data = try Data(contentsOf: out)
        let reader = try ZipArchiveReader(data: data)
        let entry = try XCTUnwrap(reader.entry(at: "word/document.xml"))
        XCTAssertEqual(entry.method, 8, "deflate로 저장돼 있어야 이 시험이 의미가 있다")
        XCTAssertLessThan(entry.compressedSize, entry.uncompressedSize / 3)

        let result = try DocxImporter.importDocument(from: data, fallbackTitle: "x")
        XCTAssertEqual(result.note.title, "보고서")
        XCTAssertEqual(result.note.document.content.count, 200)
        XCTAssertTrue(result.note.plainText.contains("반복되는 문장 200"))
    }

    func testZipReaderHandlesTrailingComment() throws {
        var data = stored(files: ["a.txt": Data("hello".utf8)])
        // EOCD의 주석 길이를 늘려 끝에 주석을 붙인다.
        let comment = Data("comment".utf8)
        data.replaceSubrange((data.count - 2)..<data.count, with: [UInt8(comment.count), 0])
        data.append(comment)
        let reader = try ZipArchiveReader(data: data)
        XCTAssertEqual(try reader.read("a.txt"), Data("hello".utf8))
    }
}
