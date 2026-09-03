import XCTest
import WebKit
@testable import NotepadX

/// 왼쪽 문서 개요 패널(DocumentOutlineView.swift)이 딛고 서는 JS 쪽 파이프라인을 검증한다:
/// 제목이 바뀔 때마다 `headingsChanged`로 (pos, level, text) 목록이 넘어오는지, 그리고
/// `scrollToHeading` 커맨드가 실제로 그 위치로 커서를 옮기는지(→ selectionChanged로 확인).
@MainActor
final class WebEditorOutlineTests: XCTestCase {
    private final class OutlineCapturingWaiter: NSObject, EditorBridgeDelegate {
        var continuation: CheckedContinuation<Void, Never>?
        var lastHeadings: [HeadingOutlineItem] = []
        var lastSelection: EditorSelectionState?

        func editorBridgeDidBecomeReady(_ bridge: EditorBridge) {
            continuation?.resume()
            continuation = nil
        }
        func editorBridge(_ bridge: EditorBridge, didChangeDocument document: EditorDocument, plainText: String) {}
        func editorBridge(_ bridge: EditorBridge, didChangeHeadings headings: [HeadingOutlineItem]) {
            lastHeadings = headings
        }
        func editorBridge(_ bridge: EditorBridge, didChangeSelection selection: EditorSelectionState) {
            lastSelection = selection
        }
        func editorBridge(_ bridge: EditorBridge, didRequestOpenExternalLink url: URL) {}
        func editorBridge(_ bridge: EditorBridge, didRequestSaveAttachment payload: SaveAttachmentPayload) {}
        func editorBridge(_ bridge: EditorBridge, didRequestOpenAttachment payload: OpenAttachmentPayload) {}
        func editorBridge(_ bridge: EditorBridge, didReportError message: String) {}
    }

    private func makeReadyController() async -> (RichEditorController, OutlineCapturingWaiter) {
        let controller = RichEditorController()
        let waiter = OutlineCapturingWaiter()
        controller.delegate = waiter
        controller.setEditable(true)
        await withCheckedContinuation { continuation in
            waiter.continuation = continuation
        }
        _ = try? await controller.webView.evaluateJavaScript(
            "document.querySelector('#editor-root .ProseMirror').focus(); true;"
        )
        return (controller, waiter)
    }

    private func pastePlainText(_ text: String, into controller: RichEditorController) async throws {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")
        let script = """
        (function() {
            const dataTransfer = new DataTransfer();
            dataTransfer.setData('text/plain', `\(escaped)`);
            const target = document.querySelector('#editor-root .ProseMirror');
            target.focus();
            const event = new ClipboardEvent('paste', { clipboardData: dataTransfer, bubbles: true, cancelable: true });
            target.dispatchEvent(event);
            return true;
        })();
        """
        _ = try await controller.webView.evaluateJavaScript(script)
        try await Task.sleep(nanoseconds: 250_000_000)
    }

    func testHeadingsChangedReportsLevelsAndTextInDocumentOrder() async throws {
        let (controller, waiter) = await makeReadyController()
        try await pastePlainText("# 제목1\n\n본문\n\n## 제목2\n\n### 제목3", into: controller)

        XCTAssertEqual(waiter.lastHeadings.map(\.level), [1, 2, 3])
        XCTAssertEqual(waiter.lastHeadings.map(\.text), ["제목1", "제목2", "제목3"])
        XCTAssertEqual(waiter.lastHeadings.map(\.pos).sorted(), waiter.lastHeadings.map(\.pos), "제목은 문서 순서(오름차순 pos)로 와야 개요 트리가 올바르게 만들어진다")
    }

    func testHeadingOutlineBuilderNestsByLevelSkippingIntermediateLevels() {
        let headings = [
            HeadingOutlineItem(pos: 0, level: 1, text: "H1"),
            HeadingOutlineItem(pos: 10, level: 3, text: "H3 (H2 건너뜀)"),
            HeadingOutlineItem(pos: 20, level: 2, text: "H2"),
            HeadingOutlineItem(pos: 30, level: 1, text: "H1-2"),
        ]

        let tree = HeadingOutlineBuilder.buildTree(from: headings)

        XCTAssertEqual(tree.map(\.item.text), ["H1", "H1-2"], "최상위 레벨 제목만 트리의 루트가 되어야 한다")
        XCTAssertEqual(tree[0].children.map(\.item.text), ["H3 (H2 건너뜀)", "H2"], "H1의 자식으로 그 뒤에 나온 더 깊은 레벨 제목들이 모두 들어가야 한다")
        XCTAssertTrue(tree[1].children.isEmpty)
    }

    func testScrollToHeadingMovesSelectionToReportedPosition() async throws {
        let (controller, waiter) = await makeReadyController()
        try await pastePlainText("# 제목1\n\n본문\n\n## 제목2", into: controller)
        guard let secondHeading = waiter.lastHeadings.last else {
            return XCTFail("headingsChanged로 제목이 하나도 넘어오지 않았다")
        }

        controller.applyCommand("scrollToHeading", args: ["pos": secondHeading.pos])
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(waiter.lastSelection?.from, secondHeading.pos, "scrollToHeading은 커서를 그 제목의 pos로 옮겨야 한다")
    }
}
