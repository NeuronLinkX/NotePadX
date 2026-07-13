import XCTest
@testable import NotepadX

final class EditorDocumentTests: XCTestCase {
    func testPlainTextRoundTrip() throws {
        let text = "첫 줄\n둘째 줄\n#include <iostream>"
        let document = EditorDocument.fromPlainText(text)

        let data = try document.encoded()
        let decoded = try EditorDocument.decode(from: data)

        XCTAssertEqual(decoded.schemaVersion, EditorDocument.currentSchemaVersion)
        XCTAssertEqual(decoded.derivedPlainText, text)
    }

    func testEmptyPlainTextProducesSingleEmptyParagraph() throws {
        let document = EditorDocument.fromPlainText("")
        XCTAssertEqual(document.content.count, 1)
        XCTAssertEqual(document.content.first?.type, "paragraph")
    }

    func testUnknownNodeTypeDoesNotCorruptDocument() throws {
        let json = """
        {
          "schemaVersion": 1,
          "type": "doc",
          "content": [
            { "type": "futureBlockFromNewerVersion", "attrs": { "custom": "value" } },
            { "type": "paragraph", "content": [ { "type": "text", "text": "hello" } ] }
          ]
        }
        """
        let decoded = try EditorDocument.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.content.count, 2)
        XCTAssertEqual(decoded.content[0].type, "futureBlockFromNewerVersion")
        XCTAssertEqual(decoded.content[1].type, "paragraph")
    }

    func testCodeBlockNodeCarriesLanguageAttribute() throws {
        let node = EditorNode(
            type: .codeBlock,
            attrs: ["language": .string("cpp")],
            content: [.textNode("#include <iostream>")]
        )
        let document = EditorDocument(content: [node])
        let decoded = try EditorDocument.decode(from: document.encoded())

        guard case .string(let language)? = decoded.content.first?.attrs?["language"] else {
            return XCTFail("language attribute missing")
        }
        XCTAssertEqual(language, "cpp")
    }
}
