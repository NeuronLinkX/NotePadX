import XCTest
import WebKit
@testable import NotepadX

/// .md 파일 등에서 복사한 순수 텍스트(clipboard에 text/html이 없는 경우)를 붙여넣으면
/// "# 제목" 같은 글자 그대로가 아니라 실제 서식으로 들어가는지 검증한다. 실제 `paste`
/// ClipboardEvent를 dispatch해서 handlePaste → markdownTextToSanitizedHTML 파이프라인을
/// 그대로 태운다(WebEditorNewFeatureTests.swift와 같은 패턴).
@MainActor
final class WebEditorMarkdownPasteTests: XCTestCase {
    private final class ReadyWaiter: NSObject, EditorBridgeDelegate {
        var continuation: CheckedContinuation<Void, Never>?
        func editorBridgeDidBecomeReady(_ bridge: EditorBridge) {
            continuation?.resume()
            continuation = nil
        }
        func editorBridge(_ bridge: EditorBridge, didChangeDocument document: EditorDocument, plainText: String) {}
        func editorBridge(_ bridge: EditorBridge, didChangeHeadings headings: [HeadingOutlineItem]) {}
        func editorBridge(_ bridge: EditorBridge, didChangeSelection selection: EditorSelectionState) {}
        func editorBridge(_ bridge: EditorBridge, didRequestOpenExternalLink url: URL) {}
        func editorBridge(_ bridge: EditorBridge, didRequestSaveAttachment payload: SaveAttachmentPayload) {}
        func editorBridge(_ bridge: EditorBridge, didRequestOpenAttachment payload: OpenAttachmentPayload) {}
        func editorBridge(_ bridge: EditorBridge, didReportError message: String) {}
    }

    private func makeReadyController() async -> RichEditorController {
        let controller = RichEditorController()
        let waiter = ReadyWaiter()
        controller.delegate = waiter
        controller.setEditable(true)
        await withCheckedContinuation { continuation in
            waiter.continuation = continuation
        }
        _ = try? await controller.webView.evaluateJavaScript(
            "document.querySelector('#editor-root .ProseMirror').focus(); true;"
        )
        return controller
    }

    /// 클립보드에 text/plain만 채우고(text/html 없이) paste 이벤트를 보낸다 — .md 파일을
    /// 텍스트 편집기나 터미널에서 복사했을 때와 같은 clipboard 구성이다.
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
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    private func editorInnerHTML(_ controller: RichEditorController) async throws -> String {
        let result = try await controller.webView.evaluateJavaScript(
            "document.querySelector('#editor-root .ProseMirror').innerHTML"
        )
        return (result as? String) ?? ""
    }

    func testPastingMarkdownHeadingRendersAsHeading() async throws {
        let controller = await makeReadyController()
        try await pastePlainText("# 제목입니다", into: controller)

        let html = try await editorInnerHTML(controller)
        XCTAssertTrue(html.contains("<h1"), "마크다운 '#' 제목은 <h1>으로 렌더링되어야 한다: \(html)")
        XCTAssertFalse(html.contains("# 제목입니다"), "'#' 문자가 그대로 문단에 남아 있으면 안 된다")
    }

    func testPastingMarkdownListRendersAsList() async throws {
        let controller = await makeReadyController()
        try await pastePlainText("- 첫째\n- 둘째\n- 셋째", into: controller)

        let html = try await editorInnerHTML(controller)
        XCTAssertTrue(html.contains("<ul"), "마크다운 불릿 목록은 <ul>로 렌더링되어야 한다: \(html)")
        XCTAssertEqual(html.components(separatedBy: "<li").count - 1, 3)
    }

    func testPastingMarkdownTaskListRendersAsInteractiveTaskItems() async throws {
        let controller = await makeReadyController()
        try await pastePlainText("- [ ] 할 일\n- [x] 끝낸 일", into: controller)

        let html = try await editorInnerHTML(controller)
        XCTAssertTrue(html.contains("data-type=\"taskList\""), "체크리스트는 Tiptap TaskList로 변환되어야 한다: \(html)")
        XCTAssertTrue(html.contains("data-checked=\"true\""), "'- [x]'는 checked 상태로 들어가야 한다: \(html)")
        XCTAssertTrue(html.contains("data-checked=\"false\""), "'- [ ]'는 unchecked 상태로 들어가야 한다: \(html)")
    }

    func testPastingMarkdownCodeFenceRendersAsCodeBlock() async throws {
        let controller = await makeReadyController()
        try await pastePlainText("```js\nconst x = 1;\n```", into: controller)

        let html = try await editorInnerHTML(controller)
        XCTAssertTrue(html.contains("<pre") && html.contains("<code"), "펜스 코드블록은 <pre><code>로 렌더링되어야 한다: \(html)")
    }

    /// 마크다운 문법 신호가 전혀 없는 평범한 문장은 그대로 문단으로 들어가야 한다 — 예를 들어
    /// "저는 *진짜* 기쁩니다" 같은 흔한 문장의 별표까지 기울임으로 바뀌면 사용자가 놀란다.
    func testPastingPlainProseWithoutMarkdownSignaturesStaysLiteral() async throws {
        let controller = await makeReadyController()
        try await pastePlainText("오늘 회의는 3시입니다.", into: controller)

        let html = try await editorInnerHTML(controller)
        XCTAssertTrue(html.contains("오늘 회의는 3시입니다."), "평범한 문장은 그대로 텍스트로 남아야 한다: \(html)")
        XCTAssertFalse(html.contains("<h1") || html.contains("<ul") || html.contains("<strong"))
    }
}
