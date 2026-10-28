import XCTest
@testable import NotepadX

final class HTMLNoteConverterTests: XCTestCase {
    private func types(_ html: String) -> [String] { HTMLNoteConverter.convert(html: html).map(\.type) }

    func testAppleNotesStyleBody() {
        let html = "<div><h1>장보기</h1></div><div>우유와 <b>달걀</b></div><div><br></div><div>끝</div>"
        let nodes = HTMLNoteConverter.convert(html: html)
        XCTAssertEqual(nodes.map(\.type), ["heading", "paragraph", "paragraph", "paragraph"])
        XCTAssertEqual(nodes[1].content?.map { $0.text ?? "" }, ["우유와 ", "달걀"])
        XCTAssertEqual(nodes[1].content?[1].marks?.first?.type, "bold")
        XCTAssertEqual(nodes[2].content?.isEmpty ?? true, true, "빈 줄은 빈 문단")
    }

    func testTitleDuplicateRemovedFromBody() {
        let note = HTMLNoteConverter.importedNote(name: "장보기", html: "<div><h1>장보기</h1></div><div>우유</div>", fallbackTitle: "x")
        XCTAssertEqual(note.title, "장보기")
        XCTAssertEqual(note.plainText, "우유")
    }

    func testTitleIsKeptWhenBodyStartsDifferently() {
        let note = HTMLNoteConverter.importedNote(name: "제목", html: "<div>다른 첫 줄</div>", fallbackTitle: "x")
        XCTAssertEqual(note.plainText, "다른 첫 줄")
    }

    func testEmptyNameFallsBack() {
        let note = HTMLNoteConverter.importedNote(name: "  ", html: "<div>내용</div>", fallbackTitle: "이름 없는 메모")
        XCTAssertEqual(note.title, "이름 없는 메모")
    }

    func testNestedLists() {
        let html = "<ul><li>a<ul><li>a1</li><li>a2</li></ul></li><li>b</li></ul><ol><li>하나</li></ol>"
        let nodes = HTMLNoteConverter.convert(html: html)
        XCTAssertEqual(nodes.map(\.type), ["bulletList", "orderedList"])
        let first = nodes[0].content?[0]
        XCTAssertEqual(first?.content?.map(\.type), ["paragraph", "bulletList"])
        XCTAssertEqual(first?.content?[1].content?.count, 2)
        XCTAssertEqual(first?.content?[0].content?.first?.text, "a")
    }

    func testEntitiesAndCollapsedWhitespace() {
        let nodes = HTMLNoteConverter.convert(html: "<div>A &amp; B &lt;c&gt; &#54620;&#xAE00;\n   끝</div>")
        XCTAssertEqual(nodes.first?.content?.first?.text, "A & B <c> 한글 끝")
    }

    func testLinkAndStyleMarks() {
        let nodes = HTMLNoteConverter.convert(html: #"<div><a href="https://x.dev/a?b=1&amp;c=2">링크</a> <u>밑줄</u> <i>기울</i> <s>취소</s></div>"#)
        let content = nodes[0].content ?? []
        XCTAssertEqual(content.first?.marks?.first?.attrs?["href"], .string("https://x.dev/a?b=1&c=2"))
        XCTAssertEqual(content.first { $0.text == "밑줄" }?.marks?.first?.type, "underline")
        XCTAssertEqual(content.first { $0.text == "기울" }?.marks?.first?.type, "italic")
        XCTAssertEqual(content.first { $0.text == "취소" }?.marks?.first?.type, "strike")
    }

    func testTable() {
        let html = "<table><tbody><tr><td>이름</td><td>값</td></tr><tr><td>a</td><td>1</td></tr></tbody></table>"
        let table = HTMLNoteConverter.convert(html: html)[0]
        XCTAssertEqual(table.type, "table")
        XCTAssertEqual(table.content?[0].content?.map(\.type), ["tableHeader", "tableHeader"])
        XCTAssertEqual(table.content?[1].content?.map(\.type), ["tableCell", "tableCell"])
        XCTAssertEqual(EditorDocument(content: [table]).derivedPlainText.contains("이름"), true)
    }

    func testDataURIImageKeptOtherImagesDropped() {
        let nodes = HTMLNoteConverter.convert(html: #"<div>앞</div><img src="data:image/png;base64,AAAA"><img src="https://x/y.png">"#)
        XCTAssertEqual(nodes.map(\.type), ["paragraph", "image"])
    }

    func testBrokenHTMLDoesNotLoseTextOrCrash() {
        let nodes = HTMLNoteConverter.convert(html: "<div>열림<b>굵게<div>다음 줄</div> 끝")
        let text = EditorDocument(content: nodes).derivedPlainText
        XCTAssertTrue(text.contains("열림"))
        XCTAssertTrue(text.contains("다음 줄"))
        XCTAssertTrue(text.contains("끝"))
        _ = HTMLNoteConverter.convert(html: "<<<>>> & <div")
    }

    func testScriptAndStyleAreIgnored() {
        let text = EditorDocument(content: HTMLNoteConverter.convert(html: "<style>div{color:red}</style><div>보임</div><script>alert(1)</script>")).derivedPlainText
        XCTAssertEqual(text, "보임")
    }

    func testPreBecomesCodeBlockAndBrIsHardBreak() {
        XCTAssertEqual(types("<pre>let a = 1\nlet b = 2</pre>"), ["codeBlock"])
        let nodes = HTMLNoteConverter.convert(html: "<div>가<br>나</div>")
        XCTAssertEqual(nodes[0].content?.map(\.type), ["text", "hardBreak", "text"])
    }
}
