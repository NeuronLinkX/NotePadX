import XCTest
@testable import NotepadX

final class MarkdownImporterTests: XCTestCase {
    private func parse(_ text: String, title: String = "파일이름") -> ImportedNote {
        MarkdownImporter.parse(text, fallbackTitle: title)
    }

    private func types(_ note: ImportedNote) -> [String] { note.document.content.map(\.type) }

    func testFirstH1BecomesTitleAndIsRemovedFromBody() {
        let note = parse("# 회의록\n\n본문입니다.")
        XCTAssertEqual(note.title, "회의록")
        XCTAssertEqual(types(note), ["paragraph"])
        XCTAssertEqual(note.plainText, "본문입니다.")
    }

    func testFallsBackToFilenameWhenNoH1() {
        let note = parse("## 소제목\n\n내용", title: "메모")
        XCTAssertEqual(note.title, "메모")
        XCTAssertEqual(types(note), ["heading", "paragraph"])
        XCTAssertEqual(note.document.content[0].attrs?["level"], .number(2))
    }

    func testLaterH1IsKept() {
        let note = parse("먼저 문단\n\n# 나중 제목")
        XCTAssertEqual(note.title, "파일이름")
        XCTAssertEqual(types(note), ["paragraph", "heading"])
    }

    func testInlineMarks() {
        let note = parse("**굵게** *기울임* ~~취소~~ `코드` [링크](https://example.com)")
        let nodes = note.document.content[0].content ?? []
        func marks(_ text: String) -> [String] {
            nodes.first { $0.text == text }?.marks?.map(\.type) ?? []
        }
        XCTAssertEqual(marks("굵게"), ["bold"])
        XCTAssertEqual(marks("기울임"), ["italic"])
        XCTAssertEqual(marks("취소"), ["strike"])
        XCTAssertEqual(marks("코드"), ["code"])
        XCTAssertEqual(marks("링크"), ["link"])
        XCTAssertEqual(nodes.first { $0.text == "링크" }?.marks?.first?.attrs?["href"], .string("https://example.com"))
    }

    func testSnakeCaseUnderscoresAreNotEmphasis() {
        let note = parse("변수 snake_case_name 을 쓴다")
        XCTAssertEqual(note.plainText, "변수 snake_case_name 을 쓴다")
    }

    func testBulletAndOrderedLists() {
        let note = parse("- 하나\n- 둘\n\n1. 첫째\n2. 둘째")
        XCTAssertEqual(types(note), ["bulletList", "orderedList"])
        XCTAssertEqual(note.document.content[0].content?.count, 2)
        XCTAssertEqual(note.document.content[1].content?.count, 2)
    }

    func testNestedList() {
        let note = parse("- 부모\n  - 자식\n  - 자식2\n- 부모2")
        let list = note.document.content[0]
        XCTAssertEqual(list.type, "bulletList")
        XCTAssertEqual(list.content?.count, 2)
        let firstItem = list.content?[0]
        XCTAssertEqual(firstItem?.content?.map(\.type), ["paragraph", "bulletList"])
        XCTAssertEqual(firstItem?.content?[1].content?.count, 2)
    }

    func testTaskList() {
        let note = parse("- [ ] 할 일\n- [x] 끝낸 일")
        let list = note.document.content[0]
        XCTAssertEqual(list.type, "taskList")
        XCTAssertEqual(list.content?.map(\.type), ["taskItem", "taskItem"])
        XCTAssertEqual(list.content?[0].attrs?["checked"], .bool(false))
        XCTAssertEqual(list.content?[1].attrs?["checked"], .bool(true))
        XCTAssertEqual(note.plainText, "할 일\n끝낸 일")
    }

    func testCodeFenceKeepsContentVerbatim() {
        let note = parse("```swift\nlet a = 1\n# 주석 아님\n\n- 목록 아님\n```\n뒤 문단")
        XCTAssertEqual(types(note), ["codeBlock", "paragraph"])
        XCTAssertEqual(note.document.content[0].attrs?["language"], .string("swift"))
        XCTAssertEqual(note.document.content[0].content?.first?.text, "let a = 1\n# 주석 아님\n\n- 목록 아님")
    }

    func testBlockquoteAndRule() {
        let note = parse("> 인용문\n> 둘째 줄\n\n---\n\n끝")
        XCTAssertEqual(types(note), ["blockquote", "horizontalRule", "paragraph"])
    }

    func testTable() {
        let note = parse("| 이름 | 값 |\n| --- | --- |\n| a | 1 |\n| b | 2 |")
        let table = note.document.content[0]
        XCTAssertEqual(table.type, "table")
        XCTAssertEqual(table.content?.count, 3)
        XCTAssertEqual(table.content?[0].content?.map(\.type), ["tableHeader", "tableHeader"])
        XCTAssertEqual(table.content?[1].content?.map(\.type), ["tableCell", "tableCell"])
    }

    func testPipeInParagraphIsNotATable() {
        let note = parse("a | b | c")
        XCTAssertEqual(types(note), ["paragraph"])
    }

    func testParagraphLinesJoinWithSpaceAndHardBreak() {
        let soft = parse("첫 줄\n둘째 줄")
        XCTAssertEqual(soft.plainText, "첫 줄 둘째 줄")
        let hard = parse("첫 줄  \n둘째 줄")
        XCTAssertEqual(hard.document.content[0].content?.map(\.type), ["text", "hardBreak", "text"])
    }

    func testCRLFAndEmptyInput() {
        XCTAssertEqual(parse("# 제목\r\n\r\n본문\r\n").plainText, "본문")
        let empty = parse("", title: "빈 파일")
        XCTAssertEqual(empty.title, "빈 파일")
        XCTAssertEqual(types(empty), ["paragraph"])
    }

    func testUnclosedFenceDoesNotLoseText() {
        let note = parse("```\n닫히지 않은 코드")
        XCTAssertEqual(note.plainText, "닫히지 않은 코드")
    }

    func testPlainTextKeepsEveryLine() {
        let note = MarkdownImporter.parsePlainText("# 해시는 그대로\n\n둘째\n\n\n", fallbackTitle: "텍스트")
        XCTAssertEqual(note.title, "텍스트")
        XCTAssertEqual(note.plainText, "# 해시는 그대로\n\n둘째")
    }

    func testDocumentRoundTripsThroughJSON() throws {
        let note = parse("# T\n\n- [x] a\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```\ncode\n```")
        let data = try note.document.encoded()
        XCTAssertEqual(try EditorDocument.decode(from: data), note.document)
    }
}
