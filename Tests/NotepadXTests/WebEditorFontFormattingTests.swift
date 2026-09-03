import XCTest
import WebKit
@testable import NotepadX

/// 글자 크기(5~125pt 프리셋 + 직접 입력)와 글꼴 선택이 실제로 문서에 반영되고, 다시 그
/// 텍스트를 선택했을 때 selectionChanged로 현재 값이 정확히 돌아오는지 검증한다.
@MainActor
final class WebEditorFontFormattingTests: XCTestCase {
    private final class Waiter: NSObject, EditorBridgeDelegate {
        var continuation: CheckedContinuation<Void, Never>?
        var lastDocument: EditorDocument?
        var lastSelection: EditorSelectionState?

        func editorBridgeDidBecomeReady(_ bridge: EditorBridge) {
            continuation?.resume()
            continuation = nil
        }
        func editorBridge(_ bridge: EditorBridge, didChangeDocument document: EditorDocument, plainText: String) {
            lastDocument = document
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

    private func makeReadyController() async -> (RichEditorController, Waiter) {
        let controller = RichEditorController()
        let waiter = Waiter()
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

    private func typeText(_ text: String, into webView: WKWebView) async {
        for character in text {
            guard let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0, context: nil, characters: String(character), charactersIgnoringModifiers: String(character),
                isARepeat: false, keyCode: 0
            ) else { continue }
            webView.keyDown(with: event)
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
    }

    private func fontStyleAttrs(_ document: EditorDocument) -> [String: JSONValue]? {
        guard let paragraph = document.content.first, let text = paragraph.content?.first,
              let mark = text.marks?.first(where: { $0.type == "textStyle" }) else { return nil }
        return mark.attrs
    }

    func testSettingAPresetFontSizeAppliesToTypedTextAndReportsBackOnSelection() async throws {
        let (controller, waiter) = await makeReadyController()
        await typeText("크게 보이게", into: controller.webView)
        controller.applyCommand("selectAll")
        try await Task.sleep(nanoseconds: 200_000_000)

        controller.applyCommand("setFontSize", args: ["size": "60pt"])
        try await Task.sleep(nanoseconds: 300_000_000)

        guard let document = waiter.lastDocument, case .string(let fontSize)? = fontStyleAttrs(document)?["fontSize"] else {
            return XCTFail("문서에 fontSize가 반영되지 않았다: \(String(describing: waiter.lastDocument))")
        }
        XCTAssertEqual(fontSize, "60pt")
        // AllSelection(전체 선택)은 문서 경계까지 걸치기 때문에 getAttributes가 마크를
        // 일관되게 못 읽는 경우가 있다 — 스타일이 적용된 글자 한가운데로 캐럿(collapsed
        // selection)을 옮겨서 확인해야 툴바가 실제로 보여줄 값과 같은 방식으로 검증된다.
        // scrollToHeading은 위치(pos)로 캐럿을 옮기는 기존 커맨드를 그대로 재사용한 것.
        controller.applyCommand("scrollToHeading", args: ["pos": 2])
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(waiter.lastSelection?.fontSize, "60pt", "글자 크기가 적용된 글자 안으로 캐럿을 옮기면 selectionChanged가 그 값을 보고해야 한다")
    }

    /// 프리셋(5·10·15·20·50·60·100·125) 사이에 있는 값도 "직접 입력"으로 자유롭게 넣을 수
    /// 있어야 한다는 요청을 검증한다 — 37은 어느 프리셋에도 없는 값이다.
    func testArbitraryPointValueBetweenPresetsCanBeApplied() async throws {
        let (controller, waiter) = await makeReadyController()
        await typeText("사이값", into: controller.webView)
        controller.applyCommand("selectAll")
        try await Task.sleep(nanoseconds: 200_000_000)

        controller.applyCommand("setFontSize", args: ["size": "37pt"])
        try await Task.sleep(nanoseconds: 300_000_000)

        guard let document = waiter.lastDocument, case .string(let fontSize)? = fontStyleAttrs(document)?["fontSize"] else {
            return XCTFail("37pt처럼 프리셋에 없는 값이 반영되지 않았다")
        }
        XCTAssertEqual(fontSize, "37pt")
    }

    func testUnsetFontSizeRemovesTheAttribute() async throws {
        let (controller, waiter) = await makeReadyController()
        await typeText("원래대로", into: controller.webView)
        controller.applyCommand("selectAll")
        try await Task.sleep(nanoseconds: 200_000_000)
        controller.applyCommand("setFontSize", args: ["size": "100pt"])
        try await Task.sleep(nanoseconds: 300_000_000)

        controller.applyCommand("selectAll")
        try await Task.sleep(nanoseconds: 100_000_000)
        controller.applyCommand("unsetFontSize")
        try await Task.sleep(nanoseconds: 300_000_000)

        let document = try XCTUnwrap(waiter.lastDocument)
        if let attrs = fontStyleAttrs(document), case .string? = attrs["fontSize"] {
            XCTFail("기본값으로 되돌린 뒤에도 fontSize가 남아 있다: \(attrs)")
        }
    }

    func testSettingAFontFamilyAppliesAndReportsBackOnSelection() async throws {
        let (controller, waiter) = await makeReadyController()
        await typeText("다른글꼴", into: controller.webView)
        controller.applyCommand("selectAll")
        try await Task.sleep(nanoseconds: 200_000_000)

        controller.applyCommand("setFontFamily", args: ["family": "Menlo"])
        try await Task.sleep(nanoseconds: 300_000_000)

        guard let document = waiter.lastDocument, case .string(let fontFamily)? = fontStyleAttrs(document)?["fontFamily"] else {
            return XCTFail("문서에 fontFamily가 반영되지 않았다: \(String(describing: waiter.lastDocument))")
        }
        XCTAssertEqual(fontFamily, "Menlo")
        // 위 fontSize 테스트와 같은 이유로, 전체 선택이 아니라 스타일 적용된 글자 안으로
        // 캐럿을 옮겨서 확인한다.
        controller.applyCommand("scrollToHeading", args: ["pos": 2])
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(waiter.lastSelection?.fontFamily, "Menlo", "글꼴이 적용된 글자 안으로 캐럿을 옮기면 selectionChanged가 그 값을 보고해야 한다")
    }
}
