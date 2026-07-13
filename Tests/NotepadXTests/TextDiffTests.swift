import XCTest
@testable import NotepadX

final class TextDiffTests: XCTestCase {
    func testIdenticalTextProducesOnlyUnchangedLines() {
        let lines = TextDiff.compute(old: "a\nb\nc", new: "a\nb\nc")
        XCTAssertTrue(lines.allSatisfy { $0.kind == .unchanged })
        XCTAssertEqual(lines.map(\.text), ["a", "b", "c"])
    }

    func testDetectsAddedAndRemovedLines() {
        let lines = TextDiff.compute(old: "first\nsecond\nthird", new: "first\nsecond changed\nthird\nfourth")

        XCTAssertTrue(lines.contains { $0.text == "second" && $0.kind == .removed })
        XCTAssertTrue(lines.contains { $0.text == "second changed" && $0.kind == .added })
        XCTAssertTrue(lines.contains { $0.text == "fourth" && $0.kind == .added })
        XCTAssertTrue(lines.contains { $0.text == "first" && $0.kind == .unchanged })
        XCTAssertTrue(lines.contains { $0.text == "third" && $0.kind == .unchanged })
    }
}
