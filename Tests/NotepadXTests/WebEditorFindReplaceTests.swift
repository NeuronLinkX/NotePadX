import XCTest
import WebKit
@testable import NotepadX

/// 찾기 및 바꾸기(Cmd+Option+F)와 줄 번호 이동(Cmd+L), 상태 표시줄의 줄·열 계산이 딛고
/// 서는 JS 쪽 파이프라인(editor.js의 findAllRanges/replaceCurrentMatch/replaceAll/goToLine)을
/// 검증한다. loadDocument로 문단 구조를 결정적으로 세팅한다(paste는 마크다운 휴리스틱을
/// 타서 줄바꿈이 어떻게 문단으로 쪼개질지 테스트마다 보장하기 어렵다).
@MainActor
final class WebEditorFindReplaceTests: XCTestCase {
    private final class SelectionCapturingWaiter: NSObject, EditorBridgeDelegate {
        var continuation: CheckedContinuation<Void, Never>?
        var lastPlainText: String = ""
        var lastSelection: EditorSelectionState?

        func editorBridgeDidBecomeReady(_ bridge: EditorBridge) {
            continuation?.resume()
            continuation = nil
        }
        func editorBridge(_ bridge: EditorBridge, didChangeDocument document: EditorDocument, plainText: String) {
            lastPlainText = plainText
        }
        func editorBridge(_ bridge: EditorBridge, didChangeHeadings headings: [HeadingOutlineItem]) {}
        func editorBridge(_ bridge: EditorBridge, didChangeSelection selection: EditorSelectionState) {
            lastSelection = selection
        }
        func editorBridge(_ bridge: EditorBridge, didRequestOpenExternalLink url: URL) {}
        func editorBridge(_ bridge: EditorBridge, didRequestSaveAttachment payload: SaveAttachmentPayload) {}
        func editorBridge(_ bridge: EditorBridge, didRequestOpenAttachment payload: OpenAttachmentPayload) {}
        func editorBridge(_ bridge: EditorBridge, didReportError message: String) {}
    }

    private func makeController(withParagraphs lines: [String]) async -> (RichEditorController, SelectionCapturingWaiter) {
        let controller = RichEditorController()
        let waiter = SelectionCapturingWaiter()
        controller.delegate = waiter
        controller.setEditable(true)
        await withCheckedContinuation { continuation in
            waiter.continuation = continuation
        }
        controller.loadDocument(EditorDocument(content: lines.map(EditorNode.paragraph)))
        try? await Task.sleep(nanoseconds: 200_000_000)
        return (controller, waiter)
    }

    func testReplaceCurrentMatchReplacesOnlyTheNextOccurrenceAndAdvances() async throws {
        let (controller, waiter) = await makeController(withParagraphs: ["foo bar foo baz foo"])

        controller.applyCommand("scrollToHeading", args: ["pos": 0]) // 커서를 문서 맨 앞으로.
        try await Task.sleep(nanoseconds: 200_000_000)

        controller.replaceCurrentMatch(query: "foo", replacement: "QUX", caseSensitive: false)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(waiter.lastPlainText, "QUX bar foo baz foo", "커서 이후 첫 일치 항목 하나만 바뀌어야 한다")
    }

    func testReplaceAllReplacesEveryOccurrence() async throws {
        let (controller, waiter) = await makeController(withParagraphs: ["foo bar foo baz foo"])

        controller.replaceAll(query: "foo", replacement: "QUX", caseSensitive: false)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(waiter.lastPlainText, "QUX bar QUX baz QUX", "일치하는 항목을 모두 바꿔야 한다")
    }

    func testReplaceAllRespectsCaseSensitivity() async throws {
        let (controller, waiter) = await makeController(withParagraphs: ["Foo foo FOO"])

        controller.replaceAll(query: "foo", replacement: "x", caseSensitive: true)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(waiter.lastPlainText, "Foo x FOO", "대소문자 구분 켜면 정확히 일치하는 것만 바꿔야 한다")
    }

    func testReplaceAllAcrossMultipleParagraphsOnlyTouchesMatchingBlocks() async throws {
        let (controller, waiter) = await makeController(withParagraphs: ["apple pie", "apple juice"])

        controller.replaceAll(query: "apple", replacement: "pear", caseSensitive: false)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(waiter.lastPlainText, "pear pie\npear juice", "문단이 여러 개여도 각 문단 안의 일치 항목이 모두 바뀌어야 한다")
    }

    func testGoToLineMovesCursorToStartOfTargetLine() async throws {
        let (controller, waiter) = await makeController(withParagraphs: ["first", "second", "third"])

        controller.applyCommand("goToLine", args: ["line": 2])
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(waiter.lastSelection?.line, 2, "지정한 줄로 커서가 이동해야 한다")
        XCTAssertEqual(waiter.lastSelection?.column, 1, "줄의 시작(1열)으로 이동해야 한다")
    }

    func testSelectionReportsLineAndColumnAsCursorMoves() async throws {
        let (controller, waiter) = await makeController(withParagraphs: ["ab", "cdef"])

        controller.applyCommand("goToLine", args: ["line": 2])
        try await Task.sleep(nanoseconds: 200_000_000)
        guard let lineStartPos = waiter.lastSelection?.from else {
            return XCTFail("goToLine 이후 selectionChanged가 오지 않았다")
        }
        // "cdef"의 3번째 글자 뒤로 절대 위치 이동(같은 줄 안에서의 이동이라 line/column
        // 계산 규칙이 문단 경계가 아니라 실제 글자 수를 세는지까지 검증한다).
        controller.applyCommand("scrollToHeading", args: ["pos": lineStartPos + 3])
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(waiter.lastSelection?.line, 2)
        XCTAssertEqual(waiter.lastSelection?.column, 4)
    }

    func testGoToLineClampsOutOfRangeLineNumberToTheLastLine() async throws {
        let (controller, waiter) = await makeController(withParagraphs: ["only line"])

        controller.applyCommand("goToLine", args: ["line": 99])
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(waiter.lastSelection?.line, 1, "존재하는 마지막 줄로 clamp되어야 한다")
    }
}
