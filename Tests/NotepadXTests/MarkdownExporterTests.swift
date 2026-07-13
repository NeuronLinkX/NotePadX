import XCTest
@testable import NotepadX

final class MarkdownExporterTests: XCTestCase {
    private func doc(_ nodes: [EditorNode]) -> EditorDocument {
        EditorDocument(content: nodes)
    }

    func testHeadingAndParagraph() {
        let document = doc([
            EditorNode(rawType: "heading", attrs: ["level": .number(2)], content: [.textNode("제목입니다")]),
            EditorNode(type: .paragraph, content: [.textNode("본문입니다")]),
        ])
        let markdown = MarkdownExporter.export(title: "", document: document, note: nil, options: ExportOptions())
        XCTAssertTrue(markdown.contains("## 제목입니다"))
        XCTAssertTrue(markdown.contains("본문입니다"))
    }

    func testBoldItalicAndInlineCodeMarks() {
        let boldMark = EditorMark(type: .bold)
        let italicMark = EditorMark(type: .italic)
        let codeMark = EditorMark(type: .code)
        let document = doc([
            EditorNode(type: .paragraph, content: [
                .textNode("굵게", marks: [boldMark]),
                .textNode(" "),
                .textNode("기울임", marks: [italicMark]),
                .textNode(" "),
                .textNode("코드", marks: [codeMark]),
            ]),
        ])
        let markdown = MarkdownExporter.export(title: "", document: document, note: nil, options: ExportOptions())
        XCTAssertTrue(markdown.contains("**굵게**"))
        XCTAssertTrue(markdown.contains("*기울임*"))
        XCTAssertTrue(markdown.contains("`코드`"))
    }

    func testLinkMark() {
        let linkMark = EditorMark(type: .link, attrs: ["href": .string("https://example.com")])
        let document = doc([
            EditorNode(type: .paragraph, content: [.textNode("여기", marks: [linkMark])]),
        ])
        let markdown = MarkdownExporter.export(title: "", document: document, note: nil, options: ExportOptions())
        XCTAssertTrue(markdown.contains("[여기](https://example.com)"))
    }

    func testBulletList() {
        let item1 = EditorNode(rawType: "listItem", content: [.paragraph("첫째")])
        let item2 = EditorNode(rawType: "listItem", content: [.paragraph("둘째")])
        let document = doc([EditorNode(type: .bulletList, content: [item1, item2])])
        let markdown = MarkdownExporter.export(title: "", document: document, note: nil, options: ExportOptions())
        XCTAssertTrue(markdown.contains("- 첫째"))
        XCTAssertTrue(markdown.contains("- 둘째"))
    }

    func testCodeBlockWithLanguage() {
        let document = doc([
            EditorNode(type: .codeBlock, attrs: ["language": .string("cpp")], content: [.textNode("#include <iostream>")]),
        ])
        let markdown = MarkdownExporter.export(title: "", document: document, note: nil, options: ExportOptions())
        XCTAssertTrue(markdown.contains("```cpp"))
        XCTAssertTrue(markdown.contains("#include <iostream>"))
        XCTAssertTrue(markdown.contains("```\n") || markdown.hasSuffix("```"))
    }

    func testCodeBlockLineNumbersOption() {
        let document = doc([
            EditorNode(type: .codeBlock, attrs: ["language": .string("plaintext")], content: [.textNode("a\nb")]),
        ])
        var options = ExportOptions()
        options.codeBlockLineNumbers = true
        let markdown = MarkdownExporter.export(title: "", document: document, note: nil, options: options)
        XCTAssertTrue(markdown.contains("1| a"))
        XCTAssertTrue(markdown.contains("2| b"))
    }

    func testTableRendersAsMarkdownTable() {
        func cell(_ text: String) -> EditorNode {
            EditorNode(rawType: "tableCell", content: [.paragraph(text)])
        }
        let headerRow = EditorNode(rawType: "tableRow", content: [cell("이름"), cell("나이")])
        let dataRow = EditorNode(rawType: "tableRow", content: [cell("철수"), cell("10")])
        let document = doc([EditorNode(rawType: "table", content: [headerRow, dataRow])])

        let markdown = MarkdownExporter.export(title: "", document: document, note: nil, options: ExportOptions())
        XCTAssertTrue(markdown.contains("| 이름 | 나이 |"))
        XCTAssertTrue(markdown.contains("| 철수 | 10 |"))
        XCTAssertTrue(markdown.contains("| --- | --- |"))
    }

    func testTitleAndDatesIncludedWhenRequested() {
        let note = Note(documentJSON: Data(), plainText: "", contentHash: "x")
        var options = ExportOptions()
        options.includeTitle = true
        options.includeDates = true
        let markdown = MarkdownExporter.export(title: "내 노트", document: doc([]), note: note, options: options)
        XCTAssertTrue(markdown.hasPrefix("# 내 노트"))
        XCTAssertTrue(markdown.contains("생성:"))
    }
}
