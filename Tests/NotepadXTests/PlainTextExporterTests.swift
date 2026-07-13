import XCTest
@testable import NotepadX

final class PlainTextExporterTests: XCTestCase {
    func testIncludesTitleAndDatesWhenRequested() {
        let note = Note(documentJSON: Data(), plainText: "본문", contentHash: "x")
        var options = ExportOptions()
        options.includeTitle = true
        options.includeDates = true
        let text = PlainTextExporter.export(title: "제목", plainText: "본문 내용", note: note, options: options)
        XCTAssertTrue(text.hasPrefix("제목"))
        XCTAssertTrue(text.contains("생성:"))
        XCTAssertTrue(text.contains("본문 내용"))
    }

    func testOmitsTitleWhenOptionDisabled() {
        var options = ExportOptions()
        options.includeTitle = false
        options.includeDates = false
        let text = PlainTextExporter.export(title: "제목", plainText: "본문", note: nil, options: options)
        XCTAssertFalse(text.contains("제목"))
        XCTAssertEqual(text, "본문")
    }
}

final class FileNameSanitizerTests: XCTestCase {
    func testRemovesPathSeparatorsAndReservedCharacters() {
        XCTAssertEqual(FileNameSanitizer.sanitize("a/b:c*d?e\"f<g>h|i"), "a-b-c-d-e-f-g-h-i")
    }

    func testStripsLeadingDotsAndPathSeparators() {
        let result = FileNameSanitizer.sanitize("../../etc/passwd")
        // "/"는 이미 다른 문자로 치환되므로 상위 디렉터리로 이동할 방법 자체가 없고,
        // 여기서는 추가로 숨김 파일(.으로 시작)이 되는 것도 막는다.
        XCTAssertFalse(result.hasPrefix("."))
        XCTAssertFalse(result.contains("/"))
        XCTAssertTrue(result.contains("etc"))
        XCTAssertTrue(result.contains("passwd"))
    }

    func testFallsBackWhenNameBecomesEmpty() {
        XCTAssertEqual(FileNameSanitizer.sanitize("///"), "제목 없음")
    }

    func testTruncatesVeryLongNames() {
        let long = String(repeating: "a", count: 300)
        XCTAssertEqual(FileNameSanitizer.sanitize(long).count, 150)
    }
}
