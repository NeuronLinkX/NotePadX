import XCTest
@testable import NotepadX

final class OpenAIClientTests: XCTestCase {
    func testParsesContentDelta() {
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"안녕\"}}]}"
        XCTAssertEqual(OpenAIClient.parseSSELine(line), .content("안녕"))
    }

    func testParsesDoneMarker() {
        XCTAssertEqual(OpenAIClient.parseSSELine("data: [DONE]"), .done)
    }

    func testIgnoresNonDataLines() {
        XCTAssertNil(OpenAIClient.parseSSELine(": keep-alive"))
        XCTAssertNil(OpenAIClient.parseSSELine(""))
        XCTAssertNil(OpenAIClient.parseSSELine("event: message"))
    }

    func testIgnoresEmptyDataPayload() {
        XCTAssertNil(OpenAIClient.parseSSELine("data:"))
        XCTAssertNil(OpenAIClient.parseSSELine("data:   "))
    }

    func testIgnoresChunkWithoutContentDelta() {
        // 롤 전환(role만 있는 첫 청크)이나 finish_reason만 있는 마지막 청크는 흘려보낸다.
        let line = "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}"
        XCTAssertNil(OpenAIClient.parseSSELine(line))
    }

    func testIgnoresMalformedJSON() {
        XCTAssertNil(OpenAIClient.parseSSELine("data: {not valid json"))
    }
}
