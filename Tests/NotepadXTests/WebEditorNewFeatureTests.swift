import XCTest
import WebKit
@testable import NotepadX

/// `WebEditor/src/*.js`가 실제로 다시 번들링되어 반영됐는지, 그리고 그 번들이 실제 WKWebView
/// 안에서 진짜로 동작하는지를 확인한다 — JS 소스를 고쳤는데 `npm run build`를 깜빡해서
/// `dist/editor.bundle.js`가 안 바뀐 채로 커밋되는 흔한 실수를 잡기 위함이다. 번들은 esbuild로
/// 모듈 스코프에 갇히므로(`editor` 같은 내부 변수는 전역이 아님) DOM만으로 검증한다.
///
/// 화살표 자동 변환은 `document.execCommand('insertText', ...)`로는 검증할 수 없었다 — 그건
/// ProseMirror의 InputRule 파이프라인(beforeinput 기반)을 타지 않고, macOS/WebKit의 자체
/// 대시 치환("--"→"—")만 우연히 걸려서 결과가 헷갈리게 나온다(직접 확인함). 대신 실제 키보드
/// 입력과 동일한 경로를 타는 `NSEvent` keyDown을 WKWebView에 직접 보내서 검증한다.
@MainActor
final class WebEditorNewFeatureTests: XCTestCase {
    private final class ReadyWaiter: NSObject, EditorBridgeDelegate {
        var continuation: CheckedContinuation<Void, Never>?
        func editorBridgeDidBecomeReady(_ bridge: EditorBridge) {
            continuation?.resume()
            continuation = nil
        }
        func editorBridge(_ bridge: EditorBridge, didChangeDocument document: EditorDocument, plainText: String) {}
        func editorBridge(_ bridge: EditorBridge, didChangeSelection selection: EditorSelectionState) {}
        func editorBridge(_ bridge: EditorBridge, didRequestOpenExternalLink url: URL) {}
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

    /// 한 글자씩 실제 keyDown 이벤트로 보낸다 — WKWebView가 AppKit의 표준
    /// interpretKeyEvents → insertText(_:replacementRange:) 경로로 처리하게 해서,
    /// 사용자가 실제로 타이핑하는 것과 같은 입력 파이프라인을 타게 만든다. keyDown은 Web
    /// Content 프로세스로 비동기 IPC를 타므로, 다음 글자를 보내기 전에 짧게 양보해야
    /// 이벤트가 씹히지 않는다(연달아 동기적으로 보내면 첫 글자만 반영되는 걸 실제로 확인함).
    private func typeText(_ text: String, into webView: WKWebView) async {
        for character in text {
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                characters: String(character),
                charactersIgnoringModifiers: String(character),
                isARepeat: false,
                keyCode: 0
            ) else { continue }
            webView.keyDown(with: event)
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
    }

    private func textContent(of controller: RichEditorController) async throws -> String {
        let result = try await controller.webView.evaluateJavaScript(
            "document.querySelector('#editor-root .ProseMirror').textContent"
        )
        return (result as? String) ?? ""
    }

    func testTypingArrowSequenceConvertsToArrowGlyph() async throws {
        let controller = await makeReadyController()
        await typeText("-->", into: controller.webView)

        let text = try await textContent(of: controller)
        XCTAssertEqual(text, "→", "'-->'를 입력하면 화살표 문자로 바로 바뀌어야 한다")
    }

    func testTypingReverseArrowSequenceConvertsToLeftArrowGlyph() async throws {
        let controller = await makeReadyController()
        await typeText("<--", into: controller.webView)

        let text = try await textContent(of: controller)
        XCTAssertEqual(text, "←")
    }

    func testTypingArrowInTheMiddleOfOtherTextOnlyReplacesTheArrow() async throws {
        let controller = await makeReadyController()
        await typeText("go-->here", into: controller.webView)

        let text = try await textContent(of: controller)
        XCTAssertEqual(text, "go→here")
    }

    func testTypingJustTwoHyphensDoesNotConvertYet() async throws {
        let controller = await makeReadyController()
        await typeText("--", into: controller.webView)

        let text = try await textContent(of: controller)
        XCTAssertEqual(text, "--", "마지막 글자(>)까지 입력하기 전에는 바뀌면 안 된다")
    }

    /// 실제 클립보드 붙여넣기와 동일한 경로(paste 이벤트 → handlePaste → FileReader →
    /// editor.commands.setImage)를 그대로 태운다. FileReader가 비동기라 Swift 쪽에서 짧게
    /// 폴링한다 — evaluateJavaScript가 반환하는 Promise 자동 해석에 기대지 않기 위해서다.
    func testPastingAnImageFileInsertsAnImageElement() async throws {
        let controller = await makeReadyController()

        let dispatchPasteScript = """
        (function() {
            const base64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
            const byteChars = atob(base64);
            const bytes = new Uint8Array(byteChars.length);
            for (let i = 0; i < byteChars.length; i++) bytes[i] = byteChars.charCodeAt(i);
            const file = new File([bytes], 'test.png', { type: 'image/png' });
            const dataTransfer = new DataTransfer();
            dataTransfer.items.add(file);
            const target = document.querySelector('#editor-root .ProseMirror');
            target.focus();
            const event = new ClipboardEvent('paste', { clipboardData: dataTransfer, bubbles: true, cancelable: true });
            target.dispatchEvent(event);
            return true;
        })();
        """
        _ = try await controller.webView.evaluateJavaScript(dispatchPasteScript)

        let checkScript = "!!document.querySelector('#editor-root .ProseMirror img')"
        var inserted = false
        for _ in 0..<40 {
            let result = try await controller.webView.evaluateJavaScript(checkScript)
            if (result as? Bool) == true {
                inserted = true
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(inserted, "이미지를 붙여넣으면 문서에 <img>가 생겨야 한다")

        let srcResult = try await controller.webView.evaluateJavaScript(
            "document.querySelector('#editor-root .ProseMirror img').getAttribute('src')"
        )
        XCTAssertTrue(
            (srcResult as? String)?.hasPrefix("data:image/png;base64,") == true,
            "붙여넣은 이미지는 별도 파일 저장 없이 data URI로 문서에 그대로 들어가야 한다"
        )
    }

    func testPastingANonImageFileDoesNotInsertAnImage() async throws {
        let controller = await makeReadyController()

        let script = """
        (function() {
            const file = new File(['hello'], 'test.txt', { type: 'text/plain' });
            const dataTransfer = new DataTransfer();
            dataTransfer.items.add(file);
            const target = document.querySelector('#editor-root .ProseMirror');
            target.focus();
            const event = new ClipboardEvent('paste', { clipboardData: dataTransfer, bubbles: true, cancelable: true });
            target.dispatchEvent(event);
            return true;
        })();
        """
        _ = try await controller.webView.evaluateJavaScript(script)
        try await Task.sleep(nanoseconds: 200_000_000)

        let hasImage = try await controller.webView.evaluateJavaScript(
            "!!document.querySelector('#editor-root .ProseMirror img')"
        )
        XCTAssertEqual(hasImage as? Bool, false)
    }
}
