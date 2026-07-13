import XCTest
@testable import NotepadX

/// DOCX는 "확장자만 바꾼 파일"이 아니라 실제 OOXML(ZIP) 패키지여야 한다는 게 스펙의 명시적 요구사항이라,
/// 여기서는 우리 코드만 믿지 않고 시스템 `/usr/bin/unzip`과 `/usr/bin/xmllint`로 실제로 열어서 검증한다.
final class DocxExporterTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NotepadXDocxTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func run(_ launchPath: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func writeSampleDocx() throws -> URL {
        let boldMark = EditorMark(type: .bold)
        let linkMark = EditorMark(type: .link, attrs: ["href": .string("https://example.com")])
        let document = EditorDocument(content: [
            EditorNode(rawType: "heading", attrs: ["level": .number(1)], content: [.textNode("보고서 제목")]),
            EditorNode(type: .paragraph, content: [
                .textNode("굵은 글씨", marks: [boldMark]),
                .textNode(" 그리고 "),
                .textNode("링크", marks: [linkMark]),
            ]),
            EditorNode(type: .codeBlock, attrs: ["language": .string("swift")], content: [.textNode("let x = 1")]),
            EditorNode(rawType: "table", content: [
                EditorNode(rawType: "tableRow", content: [
                    EditorNode(rawType: "tableCell", content: [.paragraph("A")]),
                    EditorNode(rawType: "tableCell", content: [.paragraph("B")]),
                ]),
            ]),
        ])

        let data = try DocxExporter.export(title: "보고서 제목", document: document, note: nil, options: ExportOptions())
        let url = tempDir.appendingPathComponent("sample.docx")
        try data.write(to: url)
        return url
    }

    func testGeneratedFileIsAValidZipArchive() throws {
        let url = try writeSampleDocx()
        let result = try run("/usr/bin/unzip", ["-t", url.path])
        XCTAssertEqual(result.status, 0, "unzip -t (무결성 테스트)가 실패했습니다:\n\(result.output)")
    }

    func testRequiredOOXMLPartsArePresent() throws {
        let url = try writeSampleDocx()
        let listing = try run("/usr/bin/unzip", ["-l", url.path]).output

        for requiredPart in [
            "[Content_Types].xml",
            "_rels/.rels",
            "word/document.xml",
            "word/styles.xml",
            "word/numbering.xml",
            "word/_rels/document.xml.rels",
            "docProps/core.xml",
            "docProps/app.xml",
        ] {
            XCTAssertTrue(listing.contains(requiredPart), "필수 OOXML 파트가 없습니다: \(requiredPart)")
        }
    }

    func testDocumentXMLIsWellFormed() throws {
        let url = try writeSampleDocx()
        let extractDir = tempDir.appendingPathComponent("extracted")
        _ = try run("/usr/bin/unzip", ["-o", url.path, "-d", extractDir.path])

        let documentXMLPath = extractDir.appendingPathComponent("word/document.xml").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: documentXMLPath))

        let xmllintResult = try run("/usr/bin/xmllint", ["--noout", documentXMLPath])
        XCTAssertEqual(xmllintResult.status, 0, "word/document.xml이 올바른 XML이 아닙니다:\n\(xmllintResult.output)")

        let stylesXMLPath = extractDir.appendingPathComponent("word/styles.xml").path
        let stylesResult = try run("/usr/bin/xmllint", ["--noout", stylesXMLPath])
        XCTAssertEqual(stylesResult.status, 0, "word/styles.xml이 올바른 XML이 아닙니다:\n\(stylesResult.output)")

        let numberingXMLPath = extractDir.appendingPathComponent("word/numbering.xml").path
        let numberingResult = try run("/usr/bin/xmllint", ["--noout", numberingXMLPath])
        XCTAssertEqual(numberingResult.status, 0, "word/numbering.xml이 올바른 XML이 아닙니다:\n\(numberingResult.output)")
    }

    func testDocumentXMLContainsExpectedText() throws {
        let url = try writeSampleDocx()
        let extractDir = tempDir.appendingPathComponent("extracted2")
        _ = try run("/usr/bin/unzip", ["-o", url.path, "-d", extractDir.path])

        let documentXML = try String(contentsOf: extractDir.appendingPathComponent("word/document.xml"), encoding: .utf8)
        XCTAssertTrue(documentXML.contains("보고서 제목"))
        XCTAssertTrue(documentXML.contains("굵은 글씨"))
        XCTAssertTrue(documentXML.contains("<w:b/>"), "굵게 마크가 <w:b/>로 변환돼야 한다")
        XCTAssertTrue(documentXML.contains("w:hyperlink"), "링크가 하이퍼링크 요소로 변환돼야 한다")
        XCTAssertTrue(documentXML.contains("let x = 1"))
        XCTAssertTrue(documentXML.contains("<w:tbl>"), "표가 실제 w:tbl 요소로 변환돼야 한다")

        let relsXML = try String(
            contentsOf: extractDir.appendingPathComponent("word/_rels/document.xml.rels"), encoding: .utf8
        )
        XCTAssertTrue(relsXML.contains("https://example.com"), "하이퍼링크 대상이 관계 파일에 등록돼야 한다")
    }

    func testEmptyDocumentStillProducesValidPackage() throws {
        let document = EditorDocument.fromPlainText("")
        let data = try DocxExporter.export(title: "", document: document, note: nil, options: ExportOptions())
        let url = tempDir.appendingPathComponent("empty.docx")
        try data.write(to: url)

        let result = try run("/usr/bin/unzip", ["-t", url.path])
        XCTAssertEqual(result.status, 0)
    }

    // MARK: - 자동 번호 매기기(numbering.xml)

    private func listItem(_ text: String, nested: EditorNode? = nil) -> EditorNode {
        var content: [EditorNode] = [.paragraph(text)]
        if let nested { content.append(nested) }
        return EditorNode(rawType: "listItem", content: content)
    }

    private func extractDocumentAndNumberingXML(from document: EditorDocument) throws -> (document: String, numbering: String) {
        let data = try DocxExporter.export(title: "목록 테스트", document: document, note: nil, options: ExportOptions())
        let url = tempDir.appendingPathComponent("lists-\(UUID().uuidString).docx")
        try data.write(to: url)
        let extractDir = tempDir.appendingPathComponent("extracted-\(UUID().uuidString)")
        _ = try run("/usr/bin/unzip", ["-o", url.path, "-d", extractDir.path])
        let documentXML = try String(contentsOf: extractDir.appendingPathComponent("word/document.xml"), encoding: .utf8)
        let numberingXML = try String(contentsOf: extractDir.appendingPathComponent("word/numbering.xml"), encoding: .utf8)
        return (documentXML, numberingXML)
    }

    func testBulletListProducesRealNumPrNotTextPrefix() throws {
        let document = EditorDocument(content: [
            EditorNode(type: .bulletList, content: [listItem("첫째"), listItem("둘째")]),
        ])
        let xml = try extractDocumentAndNumberingXML(from: document)

        XCTAssertTrue(xml.document.contains("<w:numPr>"), "글머리 목록이 w:numPr을 써야 진짜 목록으로 인식된다")
        XCTAssertFalse(xml.document.contains("•  <w:t"), "예전처럼 글자 접두어를 붙이면 안 된다")
        XCTAssertTrue(xml.numbering.contains("w:numFmt w:val=\"bullet\""))
    }

    func testOrderedListUsesDecimalFormat() throws {
        let document = EditorDocument(content: [
            EditorNode(type: .orderedList, content: [listItem("하나"), listItem("둘"), listItem("셋")]),
        ])
        let xml = try extractDocumentAndNumberingXML(from: document)

        XCTAssertTrue(xml.document.contains("<w:numPr>"))
        XCTAssertTrue(xml.numbering.contains("w:numFmt w:val=\"decimal\""))
    }

    func testSeparateTopLevelListsGetDistinctNumIds() throws {
        let document = EditorDocument(content: [
            EditorNode(type: .orderedList, content: [listItem("목록1-첫째"), listItem("목록1-둘째")]),
            EditorNode(type: .paragraph, content: [.textNode("사이 문단")]),
            EditorNode(type: .orderedList, content: [listItem("목록2-첫째"), listItem("목록2-둘째")]),
        ])
        let xml = try extractDocumentAndNumberingXML(from: document)

        // <w:num w:numId="1">, <w:num w:numId="2"> 두 개가 서로 다른 목록에 배정돼야
        // Word에서 두 번째 목록도 1부터 다시 시작한다.
        XCTAssertTrue(xml.numbering.contains("w:numId=\"1\""))
        XCTAssertTrue(xml.numbering.contains("w:numId=\"2\""))
    }

    func testNestedSameKindListSharesNumIdAtDeeperLevel() throws {
        let nestedBullets = EditorNode(type: .bulletList, content: [listItem("중첩 항목")])
        let document = EditorDocument(content: [
            EditorNode(type: .bulletList, content: [listItem("바깥 항목", nested: nestedBullets)]),
        ])
        let xml = try extractDocumentAndNumberingXML(from: document)

        XCTAssertTrue(xml.document.contains("w:ilvl w:val=\"0\""), "바깥 항목은 레벨 0이어야 한다")
        XCTAssertTrue(xml.document.contains("w:ilvl w:val=\"1\""), "중첩 항목은 레벨 1이어야 한다")
        // 같은 종류로 중첩됐으니 numId는 문서 전체에서 단 하나만 등록됐어야 한다.
        XCTAssertTrue(xml.numbering.contains("w:numId=\"1\""))
        XCTAssertFalse(xml.numbering.contains("w:numId=\"2\""))
    }
}
