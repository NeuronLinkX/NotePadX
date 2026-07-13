import XCTest
@testable import NotepadX

/// HTML/PDF/RTF는 실제 편집기 렌더러(WKWebView)를 다시 띄워서 만들기 때문에,
/// 단순 함수 호출 테스트가 아니라 실제로 유효한 결과물이 나오는지까지 확인한다.
@MainActor
final class ExportUseCaseTests: XCTestCase {
    private func sampleDocument() -> EditorDocument {
        EditorDocument(content: [
            EditorNode(rawType: "heading", attrs: ["level": .number(1)], content: [.textNode("통합 테스트 제목")]),
            EditorNode(type: .paragraph, content: [.textNode("본문 문단입니다.")]),
            EditorNode(type: .codeBlock, attrs: ["language": .string("swift")], content: [.textNode("let x = 42")]),
        ])
    }

    private func sampleNote() -> Note {
        Note(documentJSON: Data(), plainText: "본문 문단입니다.", contentHash: "x")
    }

    func testMarkdownExportViaUseCase() async throws {
        let output = try await ExportUseCase().export(
            note: sampleNote(), title: "제목", document: sampleDocument(), format: .markdown, options: ExportOptions()
        )
        guard case .data(let data) = output else { return XCTFail("Markdown은 Data여야 한다") }
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("# 통합 테스트 제목") || text.contains("통합 테스트 제목"))
    }

    func testJSONExportRoundTripsThroughEditorDocument() async throws {
        let output = try await ExportUseCase().export(
            note: sampleNote(), title: "제목", document: sampleDocument(), format: .json, options: ExportOptions()
        )
        guard case .data(let data) = output else { return XCTFail("JSON은 Data여야 한다") }
        let decoded = try EditorDocument.decode(from: data)
        XCTAssertEqual(decoded.content.count, sampleDocument().content.count)
    }

    func testHTMLExportProducesRenderedMarkup() async throws {
        let output = try await ExportUseCase().export(
            note: sampleNote(), title: "통합 테스트 제목", document: sampleDocument(), format: .html, options: ExportOptions()
        )
        guard case .data(let data) = output else { return XCTFail("HTML은 Data여야 한다") }
        let html = String(data: data, encoding: .utf8) ?? ""

        XCTAssertTrue(html.contains("<!doctype html>"))
        XCTAssertTrue(html.contains("통합 테스트 제목"))
        XCTAssertTrue(html.contains("본문 문단입니다"))
        // 실제 lowlight 구문강조가 "let x = 42"를 토큰별 <span>으로 쪼개므로 원문 그대로는
        // 나타나지 않는다 — 대신 강조된 토큰과 언어 클래스로 실제 렌더링됐는지 확인한다.
        XCTAssertTrue(html.contains("language-swift"))
        XCTAssertTrue(html.contains("hljs-keyword\">let<"))
        XCTAssertTrue(html.contains("hljs-number\">42<"))
        // Tiptap이 실제로 렌더링했다면 문단은 <p>, 코드 블록은 <pre><code>로 나와야 한다.
        XCTAssertTrue(html.contains("<p>"))
        XCTAssertTrue(html.contains("<pre>"))
    }

    func testPDFExportProducesValidPDFBytes() async throws {
        var options = ExportOptions()
        options.pageSize = .a4
        let output = try await ExportUseCase().export(
            note: sampleNote(), title: "통합 테스트 제목", document: sampleDocument(), format: .pdf, options: options
        )
        guard case .data(let data) = output else { return XCTFail("PDF는 Data여야 한다") }
        XCTAssertGreaterThan(data.count, 100)
        let header = data.prefix(5)
        XCTAssertEqual(String(data: header, encoding: .ascii), "%PDF-", "생성된 파일이 실제 PDF 매직 바이트로 시작하지 않는다")
    }

    func testRTFExportProducesValidRTFBytes() async throws {
        let output = try await ExportUseCase().export(
            note: sampleNote(), title: "통합 테스트 제목", document: sampleDocument(), format: .rtf, options: ExportOptions()
        )
        guard case .data(let data) = output else { return XCTFail("RTF는 Data여야 한다") }
        let header = data.prefix(6)
        XCTAssertEqual(String(data: header, encoding: .ascii), "{\\rtf1", "생성된 파일이 RTF 헤더로 시작하지 않는다")
    }

}
