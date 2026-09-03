import XCTest
import WebKit
@testable import NotepadX

/// `WebEditor/src/*.js`/`editor.css`가 실제로 다시 번들링·반영됐는지, 그리고 그게 실제
/// WKWebView 안에서 진짜로 동작하는지를 확인한다 — 소스를 고쳤는데 `npm run build`를
/// 깜빡해서 `dist/editor.bundle.js`가 안 바뀐 채로 커밋되는 흔한 실수를 잡기 위함이다.
/// 번들은 esbuild로 모듈 스코프에 갇히므로(`editor` 같은 내부 변수는 전역이 아님) DOM만으로
/// 검증한다.
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

    /// base64 PNG를 실제 클립보드 붙여넣기와 동일한 경로(paste 이벤트 → handlePaste →
    /// FileReader → editor.commands.setImage)로 삽입한다.
    private func pasteImage(base64: String, filename: String, into controller: RichEditorController) async throws {
        let script = """
        (function() {
            const base64 = '\(base64)';
            const byteChars = atob(base64);
            const bytes = new Uint8Array(byteChars.length);
            for (let i = 0; i < byteChars.length; i++) bytes[i] = byteChars.charCodeAt(i);
            const file = new File([bytes], '\(filename)', { type: 'image/png' });
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
    }

    /// 삽입된 이미지가 완전히 디코딩(naturalWidth를 알 수 있는 상태)될 때까지 기다렸다가
    /// 렌더된 박스 크기와 원본 픽셀 크기를 함께 읽어온다.
    private func waitForRenderedImageSize(in controller: RichEditorController) async throws -> (width: Double, height: Double, naturalWidth: Double, naturalHeight: Double)? {
        let script = """
        (function() {
            const img = document.querySelector('#editor-root .ProseMirror img');
            if (!img || !img.naturalWidth) return null;
            const r = img.getBoundingClientRect();
            return JSON.stringify({ w: r.width, h: r.height, naturalW: img.naturalWidth, naturalH: img.naturalHeight });
        })();
        """
        for _ in 0..<60 {
            let result = try await controller.webView.evaluateJavaScript(script)
            if let jsonString = result as? String, let data = jsonString.data(using: .utf8),
               let parsed = try? JSONDecoder().decode([String: Double].self, from: data) {
                return (parsed["w"] ?? 0, parsed["h"] ?? 0, parsed["naturalW"] ?? 0, parsed["naturalH"] ?? 0)
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    func testTypingArrowSequenceConvertsToArrowGlyph() async throws {
        let controller = await makeReadyController()
        await typeText("-->", into: controller.webView)

        let text = try await textContent(of: controller)
        XCTAssertEqual(text, "→", "\'-->\'를 입력하면 화살표 문자로 바로 바뀌어야 한다")
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

    func testPastingAnImageFileInsertsAnImageElement() async throws {
        let controller = await makeReadyController()
        try await pasteImage(
            base64: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
            filename: "test.png",
            into: controller
        )

        let size = try await waitForRenderedImageSize(in: controller)
        XCTAssertNotNil(size, "이미지를 붙여넣으면 문서에 <img>가 생겨야 한다")

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

    // MARK: - 큰 이미지 크기 제한 (버그: 원본 해상도로 붙여넣으면 패널이 이미지 하나로 꽉 참)

    /// 1000×700 픽셀 이미지를 붙여넣어도, 화면에는 폭 480px을 넘지 않게 줄어서 보여야 한다
    /// (원본 데이터 자체는 그대로 저장되고, 화면 표시만 제한한다).
    func testPastingALargeLandscapeImageIsScaledDownToFitThePane() async throws {
        let controller = await makeReadyController()
        controller.webView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        try await pasteImage(base64: "iVBORw0KGgoAAAANSUhEUgAAA+gAAAK8CAIAAADzqQLmAAAL2klEQVR42u3WMQ0AAAzDsCIpfyiDNRo9LBlBruRaAABgXCQAAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHFXAQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMuwoAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwlAAAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxVwEAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjLsKAABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAGDcJQAAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAADGHQAA2PZVXbw4r1xelQAAAABJRU5ErkJggg==", filename: "wide.png", into: controller)

        guard let size = try await waitForRenderedImageSize(in: controller) else {
            return XCTFail("이미지가 삽입되지 않았다")
        }
        XCTAssertEqual(size.naturalWidth, 1000, "원본 픽셀 크기는 그대로 유지되어야 한다(표시만 줄어듦)")
        XCTAssertLessThanOrEqual(size.width, 480, "화면에 보이는 폭은 480px을 넘으면 안 된다 — 이게 없으면 원본 해상도 사진이 패널을 꽉 채운다")
        XCTAssertGreaterThan(size.width, 0)
    }

    /// 700×1400(세로가 긴) 이미지도 세로로 패널을 다 채우지 않도록 높이가 제한되어야 한다.
    func testPastingATallPortraitImageIsHeightCapped() async throws {
        let controller = await makeReadyController()
        controller.webView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        try await pasteImage(base64: "iVBORw0KGgoAAAANSUhEUgAAArwAAAV4CAIAAADNBpk4AAAS1klEQVR42u3WMQ0AAAgEsVeCOsQiCwmsDE2q4KZL9QAAnCIBAGAaAADTAACYBgDANAAApgEAMA0AAKYBADANAIBpAABMAwBgGgAA0wAAmAYAANMAAJgGAMA0AACmAQAwDQCAaQAATAMAgGkAAEwDAGAaAADTAACYBgDANAAApgEAwDQAAKYBADANAIBpAABMAwBgGgAA0wAAYBoAANMAAJgGAMA0AACmAQAwDQCAaQAAMA0AgGkAAEwDAGAaAADTAACYBgDANAAAmAYAwDQAAKYBADANAIBpAABMAwBgGgAATAMAYBoAANMAAJgGAMA0AACmAQAwDQAApgEAMA0AgGkAAEwDAGAaAADTAACYBgAA0wAAmAYAwDQAAKYBADANAIBpAABMAwCAaQAATAMAYBoAANMAAJgGAMA0AACmAQDANAAApgEAMA0AgGkAAEwDAGAaAADTAABgGgAA0wAAmAYAwDQAAKYBADANAIBpAAAwDQCAaQAATAMAYBoAANMAAJgGAMA0AACYBgDANAAApgEAMA0AgGkAAEwDAGAaAABMAwBgGgAA0wAAmAYAwDQAAKYBADANAACmAQAwDQCAaQAATAMAYBoAANMAAJgGAADTAACYBgDANAAApgEAMA0AgGkAAEwDAIBpAABMAwBgGgAA0wAAmAYAwDQAAKYBAMA0AACmAQAwDQCAaQAATAMAYBoAANMAAGAaAADTAACYBgDANAAApgEAMA0AgGkAADANAIBpAABMAwBgGgAA0wAAmAYAwDQAAJgGAMA0AACmAQAwDQCAaQAATAMAYBoAAEwDAGAaAADTAACYBgDANAAApgEAMA0AAKYBADANAIBpAABMAwBgGgAA0wAAmAYAANMAAJgGAMA0AACmAQAwDQCAaQAATAMAgGkAAEwDAGAaAADTAACYBgDANAAApgEAwDQAAKYBADANAIBpAABMAwBgGgAA0wAAYBoAANMAAJgGAMA0AACmAQAwDQCAaQAAMA0AgGkAAEwDAGAaAADTAACYBgDANAAAmAYAwDQAAKYBADANAIBpAABMAwBgGgAATAMAYBoAANMAAJgGAMA0AACmAQAwDQAApgEAMA0AgGkAAEwDAGAaAADTAACYBgAA0wAAmAYAwDQAAKYBADANAIBpAABMgwoAgGkAAEwDAGAaAADTAACYBgDANAAApkEFAMA0AACmAQAwDQCAaQAATAMAYBoAANMgAQBgGgAA0wAAmAYAwDQAAKYBADANAACmAQAwDQCAaQAATAMAYBoAANMAAJgGAADTAACYBgDANAAApgEAMA0AgGkAAEwDAIBpAABMAwBgGgAA0wAAmAYAwDQAAKYBAMA0AACmAQAwDQCAaQAATAMAYBoAANMAAGAaAADTAACYBgDANAAApgEAMA0AgGkAADANAIBpAABMAwBgGgAA0wAAmAYAwDQAAJgGAMA0AACmAQAwDQCAaQAATAMAYBoAAEwDAGAaAADTAACYBgDANAAApgEAMA0AAKYBADANAIBpAABMAwBgGgAA0wAAmAYAANMAAJgGAMA0AACmAQAwDQCAaQAATAMAgGkAAEwDAGAaAADTAACYBgDANAAApgEAwDQAAKYBADANAIBpAABMAwBgGgAA0wAAYBoAANMAAJgGAMA0AACmAQAwDQCAaQAAMA0AgGkAAEwDAGAaAADTAACYBgDANAAAmAYAwDQAAKYBADANAIBpAABMAwBgGgAATAMAYBoAANMAAJgGAMA0AACmAQAwDQAApgEAMA0AgGkAAEwDAGAaAADTAACYBgAA0wAAmAYAwDQAAKYBADANAIBpAABMAwCAaQAATAMAYBoAANMAAJgGAMA0AACmAQDANAAApgEAMA0AgGkAAEwDAGAaAADTAABgGgAA0wAAmAYAwDQAAKYBADANAIBpAAAwDQCAaQAATAMAYBoAANMAAJgGAMA0AACYBgDANAAApgEAMA0AgGkAAEwDAGAaAABMAwBgGgAA0wAAmAYAwDQAAKYBADANAACmAQAwDQCAaQAATAMAYBoAANMAAJgGAADTAACYBgDANAAApgEAMA0AgGkAAEwDAIBpAABMAwBgGgAA0wAAmAYAwDQAAKYBAMA0AACmAQAwDQCAaQAATAMAYBoAANMAAGAaAADTAACYBgDANAAApgEAMA0AgGkAADANAIBpAABMAwBgGgAA0wAAmAYAwDQAAJgGAMA0AACmAQAwDQCAaQAATAMAYBoAAEwDAGAaAADTAACYBgDANAAApgEAMA0AAKYBADANAIBpAABMAwBgGgAA0wAAmAYAANMAAJgGAMA0AACmAQAwDQCAaQAATIMKAIBpAABMAwBgGgAA0wAAmAYAwDQAAKZBBQDANAAApgEAMA0AgGkAAEwDAGAaAADTIAEAYBoAANMAAJgGAMA0AACmAQAwDQAApgEAMA0AgGkAAEwDAGAaAADTAACYBgAA0wAAmAYAwDQAAKYBADANAIBpAABMAwCAaQAATAMAYBoAANMAAJgGAMA0AACmAQDANAAApgEAMA0AgGkAAEwDAGAaAADTAABgGgAA0wAAmAYAwDQAAKYBADANAIBpAAAwDQCAaQAATAMAYBoAANMAAJgGAMA0AACYBgDANAAApgEAMA0AgGkAAEwDAGAaAABMAwBgGgAA0wAAmAYAwDQAAKYBADANAACmAQAwDQCAaQAATAMAYBoAANMAAJgGAADTAACYBgDANAAApgEAMA0AgGkAAEwDAIBpAABMAwBgGgAA0wAAmAYAwDQAAKYBAMA0AACmAQAwDQCAaQAATAMAYBoAANMAAGAaAADTAACYBgDANAAApgEAMA0AgGkAADANAIBpAABMAwBgGgAA0wAAmAYAwDQAAJgGAMA0AACmAQAwDQCAaQAATAMAYBoAAEwDAGAaAADTAACYBgDANAAApgEAMA0AAKYBADANAIBpAABMAwBgGgAA0wAAmAYAANMAAJgGAMA0AACmAQAwDQCAaQAATAMAgGkAAEwDAGAaAADTAACYBgDANAAApgEAwDQAAKYBADANAIBpAABMAwBgGgAA0wAAYBoAANMAAJgGAMA0AACmAQAwDQCAaQAAMA0AgGkAAEwDAGAaAADTAACYBgDANAAAmAYAwDQAAKYBADANAIBpAABMAwBgGgAATAMAYBoAANMAAJgGAMA0AACmAQAwDQAApgEAMA0AgGkAAEwDAGAaAADTAACYBgAA0wAAmAYAwDQAAKYBADANAIBpAABMAwCAaQAATAMAYBoAANMAAJgGAMA0AACmAQDANAAApgEAMA0AgGkAAEwDAGAaAADTAABgGgAA0wAAmAYAwDQAAKYBADANAIBpAAAwDQCAaQAATAMAYBoAANMAAJgGAMA0AACYBgDANAAApgEAMA0AgGkAAEwDAGAaAABMAwBgGgAA0wAAmAYAwDQAAKYBADANAACmAQAwDQCAaQAATAMAYBoAANMAAJgGAADTAACYBgDANAAApgEAMA0AgGkAAEyDCgCAaQAATAMAYBoAANMAAJgGAMA0AACmQQUAwDQAAKYBADANAIBpAABMAwBgGgAA0yABAGAaAADTAACYBgDANAAApgEAMA0AAKYBADANAIBpAABMAwBgGgAA0wAAmAYAANMAAJgGAMA0AACmAQAwDQCAaQAATAMAgGkAAEwDAGAaAADTAACYBgDANAAApgEAwDQAAKYBADANAIBpAABMAwBgGgAA0wAAYBoAANMAAJgGAMA0AACmAQAwDQCAaQAAMA0AgGkAAEwDAGAaAADTAACYBgDANAAAmAYAwDQAAKYBADANAIBpAABMAwBgGgAATAMAYBoAANMAAJgGAMA0AACmAQAwDQAApgEAMA0AgGkAAEwDAGAaAADTAACYBgAA0wAAmAYAwDQAAKYBADANAIBpAABMAwCAaQAATAMAYBoAANMAAJgGAMA0AACmAQDANAAApgEAMA0AgGkAAEwDAGAaAADTAABgGgAA0wAAmAYAwDQAAKYBADANAIBpAAAwDQCAaQAATAMAYBoAANMAAJgGAMA0AACYBgDANAAApgEAMA0AgGkAAEwDAGAaAABMAwBgGgAA0wAAmAYAwDQAAKYBADANAACmAQAwDQCAaQAATAMAYBoAANMAAJgGAADTAACYBgDANAAApgEAMA0AgGkAAEwDAIBpAABMAwBgGgAA0wAAmAYAwDQAAKYBAMA0AACmAQAwDQCAaQAATAMAYBoAANMAAGAaAADTAACYBgDANAAApgEAMA0AgGkAADANAIBpAABMAwBgGgAA0wAAmAYAwDQAAJgGAMA0AACmAQAwDQCAaQAATAMAYBoAAEwDAGAaAADTAACYBgDANAAApgEAMA0AAKYBADANAIBpAABMAwBgGgAA0wAAmAYAANMAAJgGAMA0AACmAQAwDQCAaQAATAMAgGkAAEwDAGAaAADTAACYBgDANAAApgEAwDQAAKYBADANAIBpAABMAwBgGgAA0wAAYBoAANMAAJgGAMA0AACmAQAwDQCAaQAAMA0AgGkAAEwDAGAaAADTAACYBgDANAAAmAYAwDQAAKYBADANAIBpAABMAwBgGgAATAMAYBoAANMAAJgGAMA0AACmAQAwDQAApgEAMA0AgGkAAEwDAGAaAADTAACYBgAA0wAAmAYAwDQAAKYBADANAIBpAABMgwoAgGkAAEwDAGAaAADTAACYBgDANAAApkEFAMA0AACmAQAwDQCAaQAATAMAYBoAANMgAQBgGgAA0wAAmAYAwDQAAKYBADANAACmAQAwDQCAaQAATAMAYBoAANMAAJgGAADTAACYBgDANAAApgEAMA0AgGkAAEwDAIBpAABMAwBgGgAA0wAAmAYAwDQAAKYBAMA0AACmAQAwDQCAaQAATAMAYBoAANMAAGAaAADTAACYBgDANAAApgEAMA0AgGkAADANAIBpAABMAwBgGgAA0wAAmAYAwDQAAJgGAMA0AACmAQAwDQCAaQAATAMAYBoAAEwDAGAaAADTAACYBgDANAAApgEAMA0AAKYBADANAIBpAABMAwBgGgAA0wAAmAYAANMAAJgGAMA0AACmAQAwDQCAaQAATAMAgGkAAEwDAGAaAADTAACYBgDANAAApgEAwDQAAKYBADANAIBpAABMAwBgGgAA0wAAYBoAANMAAJgGAMA0AACmAQAwDQCAaQAAMA0AgGkAAEwDAGAaAADTAACYBgDANAAAmAYAwDQAAKYBADANAIBpAABMAwBgGgAATAMAYBoAANMAAJgGAMA0AACmAQAwDQAApgEAMA0AgGkAAEwDAGAaAADTAACYBgAA0wAAmAYAwDQAAKYBADANAIBpAABMAwCAaQAATAMAYBoAANMAAJgGAMA0AACmAQDANAAApgEAMA0AgGkAAEwDAGAaAADTAABgGgAA0wAAmAYAwDQAAKYBADANAIBpAAAwDQCAaQAATAMAYBoAANMAAJgGAMA0AACYBgDANAAApgEAMA0AgGkAAEwDAGAaAABMAwBgGgAA0wAAmAYAwDQAAKYBADANAACmAQAwDQCAaQAATAMAYBoAANMAAJgGAADTAACYBgDANAAApgEAMA0AgGkAAEwDAIBpAABMAwBgGgAA0wAAmAYAwDQAAKYBAMA0AACmAQAwDQCAaQAATAMAYBoAANMAAGAaAADTAACYBgDANAAApgEAMA0AgGkAADANAIBpAABMAwBgGgAA0wAAmAYAwDQAAJgGAMA0AACmAQAwDQCAaQAATAMAYBoAAEwDAGAaAADTAACYBgDANAAApgEAMA0AAKYBADANAIBpAABMAwBgGgAA0wAAmAYAANMAAJgGAMA0AACmAQAwDQCAaQAATIMKAIBpAABMAwBgGgAA0wAAmAYAwDQAAKZBBQDANAAApgEAMA0AgGkAAEwDAGAaAADTIAEAYBoAANMAAJgGAMA0AACmAQAwDQAApgEAMA0AgGkAAEwDAGAaAADTAACYBgAA0wAAmAYAwDQAAKYBADANAIBpAABMAwCAaQAATAMAYBoAANMAAJgGAMA0AACmAQDANAAApgEAMA0AgGkAAEwDAGAaAADTAABgGgAA0wAAmAYAwDQAAKYBADANAIBpAAAwDQCAaQAATAMAYBoAANMAAJgGAMA0AACYBgDANAAApgEAMA0AgGkAAEwDAGAaAABMAwBgGgAA0wAAmAYAwDQAAKYBADANAACmAQAwDQCAaQAATAMAYBoAANMAAJgGAADTAACYBgDANAAApgEAMA0AgGkAAEwDAIBpAABMAwBgGgAA0wAAmAYAwDQAAKYBAMA0AACmAQAwDQCAaQAATAMAYBoAANMAAGAaAADTAACYBgDANAAApgEAMA0AgGkAADANAIBpAABMAwBgGgAA0wAAmAYAwDQAAJgGAMA0AACmAQAwDQDAfwvWvNJqtUln9wAAAABJRU5ErkJggg==", filename: "tall.png", into: controller)

        guard let size = try await waitForRenderedImageSize(in: controller) else {
            return XCTFail("이미지가 삽입되지 않았다")
        }
        XCTAssertEqual(size.naturalHeight, 1400, "원본 픽셀 크기는 그대로 유지되어야 한다(표시만 줄어듦)")
        XCTAssertLessThanOrEqual(size.height, 480, "세로로 긴 사진도 높이가 제한되어야 패널을 다 채우지 않는다")
        XCTAssertGreaterThan(size.height, 0)
    }

    /// 편집기 안에 이미지가 하나 있어도, 좌우로 스크롤이 생기면 안 된다 — 스크롤이 생긴다는
    /// 건 max-width가 실제로는 안 먹히고 있다는 뜻이다.
    func testLargeImageDoesNotCauseHorizontalOverflow() async throws {
        let controller = await makeReadyController()
        controller.webView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        try await pasteImage(base64: "iVBORw0KGgoAAAANSUhEUgAAA+gAAAK8CAIAAADzqQLmAAAL2klEQVR42u3WMQ0AAAzDsCIpfyiDNRo9LBlBruRaAABgXCQAAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHFXAQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMuwoAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwlAAAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxVwEAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjLsKAABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAGDcJQAAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAADGHQAA2PZVXbw4r1xelQAAAABJRU5ErkJggg==", filename: "wide.png", into: controller)
        _ = try await waitForRenderedImageSize(in: controller)

        let overflowCheck = try await controller.webView.evaluateJavaScript(
            "document.body.scrollWidth <= document.body.clientWidth + 1"
        )
        XCTAssertEqual(overflowCheck as? Bool, true, "이미지 때문에 문서 전체 폭이 넓어져서 가로 스크롤이 생기면 안 된다")
    }

    // MARK: - 드래그앤드롭 / 크기 조절 / 다시 붙여넣기 (버그: 정적 삽입 후 움직이지도 크기 조절도 안 됨)

    /// Finder 등에서 사진 파일을 편집기 위로 끌어다 놓는 것과 동일한 경로(drop 이벤트 →
    /// handleDrop → FileReader → setImage)를 그대로 태운다. 이전에는 handleDrop 자체가
    /// 없어서 드래그앤드롭이 아예 아무 반응이 없었다.
    func testDroppingAnImageFileInsertsAnImageElement() async throws {
        let controller = await makeReadyController()

        let script = """
        (function() {
            const base64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
            const byteChars = atob(base64);
            const bytes = new Uint8Array(byteChars.length);
            for (let i = 0; i < byteChars.length; i++) bytes[i] = byteChars.charCodeAt(i);
            const file = new File([bytes], 'dropped.png', { type: 'image/png' });
            const dataTransfer = new DataTransfer();
            dataTransfer.items.add(file);
            const target = document.querySelector('#editor-root .ProseMirror');
            const rect = target.getBoundingClientRect();
            const event = new DragEvent('drop', {
                dataTransfer, bubbles: true, cancelable: true,
                clientX: rect.left + 10, clientY: rect.top + 10,
            });
            target.dispatchEvent(event);
            return true;
        })();
        """
        _ = try await controller.webView.evaluateJavaScript(script)

        let size = try await waitForRenderedImageSize(in: controller)
        XCTAssertNotNil(size, "사진 파일을 끌어다 놓으면 문서에 이미지가 들어가야 한다")
    }

    /// 이미지 오른쪽 아래 손잡이를 실제로 드래그해서, 저장되는 문서 JSON의 width 속성이
    /// 바뀌는지 확인한다 — CSS만 보는 게 아니라 `docChanged`로 Swift에 실제로 넘어오는
    /// 문서까지 확인해서, "화면만 커 보이고 저장은 안 됨" 같은 절반짜리 구현을 잡아낸다.
    func testDraggingResizeHandleUpdatesTheSavedWidth() async throws {
        final class DocCapturingWaiter: NSObject, EditorBridgeDelegate {
            var continuation: CheckedContinuation<Void, Never>?
            var lastDocument: EditorDocument?
            func editorBridgeDidBecomeReady(_ bridge: EditorBridge) {
                continuation?.resume()
                continuation = nil
            }
            func editorBridge(_ bridge: EditorBridge, didChangeDocument document: EditorDocument, plainText: String) {
                lastDocument = document
            }
            func editorBridge(_ bridge: EditorBridge, didChangeHeadings headings: [HeadingOutlineItem]) {}
            func editorBridge(_ bridge: EditorBridge, didChangeSelection selection: EditorSelectionState) {}
            func editorBridge(_ bridge: EditorBridge, didRequestOpenExternalLink url: URL) {}
        func editorBridge(_ bridge: EditorBridge, didRequestSaveAttachment payload: SaveAttachmentPayload) {}
        func editorBridge(_ bridge: EditorBridge, didRequestOpenAttachment payload: OpenAttachmentPayload) {}
            func editorBridge(_ bridge: EditorBridge, didReportError message: String) {}
        }

        let controller = RichEditorController()
        let waiter = DocCapturingWaiter()
        controller.delegate = waiter
        controller.setEditable(true)
        await withCheckedContinuation { continuation in waiter.continuation = continuation }
        controller.webView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)

        try await pasteImage(
            base64: "iVBORw0KGgoAAAANSUhEUgAAA+gAAAK8CAIAAADzqQLmAAAL2klEQVR42u3WMQ0AAAzDsCIpfyiDNRo9LBlBruRaAABgXCQAAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHFXAQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMuwoAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwlAAAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxVwEAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjLsKAABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAGDcJQAAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAADGHQAA2PZVXbw4r1xelQAAAABJRU5ErkJggg==",
            filename: "wide.png",
            into: controller
        )
        _ = try await waitForRenderedImageSize(in: controller)

        // 손잡이가 화면에 보이려면(opacity 전환과 무관하게 hit-test는 항상 가능하다) 좌표를 읽는다.
        let handleRectScript = """
        (function() {
            const handle = document.querySelector('.nx-image-resize-handle');
            if (!handle) return null;
            const r = handle.getBoundingClientRect();
            return JSON.stringify({ x: r.left + r.width / 2, y: r.top + r.height / 2 });
        })();
        """
        guard let handleJSON = try await controller.webView.evaluateJavaScript(handleRectScript) as? String,
              let handleData = handleJSON.data(using: .utf8),
              let handlePoint = try? JSONDecoder().decode([String: Double].self, from: handleData),
              let startX = handlePoint["x"], let startY = handlePoint["y"] else {
            return XCTFail("크기 조절 손잡이를 찾을 수 없다")
        }

        // 손잡이를 오른쪽으로 120px 끌어서 이미지를 넓힌다.
        let dragScript = """
        (function() {
            const handle = document.querySelector('.nx-image-resize-handle');
            const down = new PointerEvent('pointerdown', { clientX: \(startX), clientY: \(startY), bubbles: true, cancelable: true });
            handle.dispatchEvent(down);
            const move = new PointerEvent('pointermove', { clientX: \(startX + 120), clientY: \(startY), bubbles: true, cancelable: true });
            document.dispatchEvent(move);
            const up = new PointerEvent('pointerup', { clientX: \(startX + 120), clientY: \(startY), bubbles: true, cancelable: true });
            document.dispatchEvent(up);
            return true;
        })();
        """
        _ = try await controller.webView.evaluateJavaScript(dragScript)
        try await Task.sleep(nanoseconds: 200_000_000)

        guard let document = waiter.lastDocument, let imageNode = document.content.first(where: { $0.type == "image" }) else {
            return XCTFail("드래그 후 docChanged로 넘어온 문서에서 image 노드를 찾을 수 없다")
        }
        guard case .number(let width)? = imageNode.attrs?["width"] else {
            return XCTFail("저장된 문서의 image 노드에 width 속성이 없다 — 화면만 커지고 실제로는 저장이 안 된 것이다")
        }
        XCTAssertGreaterThan(width, 480, "480px 손잡이로 늘렸으니 저장된 width도 480보다 커야 한다")
    }

    /// 이미 삽입된 이미지를 복사해서 다시 붙여넣는(HTML 붙여넣기 경로) 시나리오. 예전에는
    /// Image 확장의 allowBase64 기본값이 false라서 data: URI가 parseHTML에서 통째로
    /// 거부되어 조용히 안 붙었다.
    func testPastingImageAsHTMLWithDataURISucceeds() async throws {
        let controller = await makeReadyController()

        let script = """
        (function() {
            const html = '<img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=">';
            const dataTransfer = new DataTransfer();
            dataTransfer.setData('text/html', html);
            const target = document.querySelector('#editor-root .ProseMirror');
            target.focus();
            const event = new ClipboardEvent('paste', { clipboardData: dataTransfer, bubbles: true, cancelable: true });
            target.dispatchEvent(event);
            return true;
        })();
        """
        _ = try await controller.webView.evaluateJavaScript(script)

        let size = try await waitForRenderedImageSize(in: controller)
        XCTAssertNotNil(size, "data: URI 이미지를 HTML로 다시 붙여넣어도(예: 복사 후 이동) 들어가야 한다 — allowBase64가 꺼져 있으면 조용히 무시된다")
    }

    /// data:image/*를 허용하도록 sanitize.js를 완화했는데, 그 김에 javascript: 링크나
    /// data:text/html 같은 진짜 위험한 스킴까지 같이 풀어버리면 안 된다 — 그 경계선을 고정한다.
    func testPastingDangerousURLSchemesIsStillBlocked() async throws {
        let controller = await makeReadyController()

        let script = """
        (function() {
            const html = '<a id="js" href="javascript:alert(1)">click</a>'
                + '<img id="htmlData" src="data:text/html,<script>alert(1)<\\/script>">'
                + '<a id="vb" href="vbscript:msgbox(1)">click</a>';
            const dataTransfer = new DataTransfer();
            dataTransfer.setData('text/html', html);
            const target = document.querySelector('#editor-root .ProseMirror');
            target.focus();
            const event = new ClipboardEvent('paste', { clipboardData: dataTransfer, bubbles: true, cancelable: true });
            target.dispatchEvent(event);
            return true;
        })();
        """
        _ = try await controller.webView.evaluateJavaScript(script)
        try await Task.sleep(nanoseconds: 200_000_000)

        let hasDangerousHref = try await controller.webView.evaluateJavaScript(
            """
            (function() {
                const links = Array.from(document.querySelectorAll('#editor-root a'));
                return links.some(a => (a.getAttribute('href') || '').startsWith('javascript:') || (a.getAttribute('href') || '').startsWith('vbscript:'));
            })();
            """
        )
        XCTAssertEqual(hasDangerousHref as? Bool, false, "javascript:/vbscript: 링크는 여전히 제거되어야 한다")

        let hasDangerousImgSrc = try await controller.webView.evaluateJavaScript(
            """
            (function() {
                const imgs = Array.from(document.querySelectorAll('#editor-root img'));
                return imgs.some(img => (img.getAttribute('src') || '').startsWith('data:text/html'));
            })();
            """
        )
        XCTAssertEqual(hasDangerousImgSrc as? Bool, false, "data:text/html 같은 실행 가능한 data URI는 여전히 제거되어야 한다")
    }

    // MARK: - 큰 사진을 붙여넣을 때 앱이 멈추는 버그

    /// 압축이 거의 안 되는 랜덤 노이즈 PNG를 만든다 — 단색/반복 패턴은 PNG의 deflate가 잘
    /// 압축해버려서 재인코딩 임계값을 실제로 넘기는 "무겁고 큰" 사진을 재현하지 못한다.
    private func randomNoisePNGBase64(width: Int, height: Int) -> String {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        if let bitmapData = rep.bitmapData {
            arc4random_buf(bitmapData, rep.bytesPerRow * height)
        }
        let pngData = rep.representation(using: .png, properties: [:])!
        return pngData.base64EncodedString()
    }

    /// 몇 MB짜리 사진을 원본 바이트 그대로 문서 JSON에 박아 넣으면, 편집할 때마다(scheduleDocChanged)
    /// 그 몇 MB짜리 base64 문자열 전체를 WKWebView의 postMessage 브리지로 다시 보내야 했다 —
    /// 이게 사진을 붙여넣는 순간 앱이 응답 없음 상태로 멈추는 버그의 원인이었다. 임계값(1.5MB)을
    /// 넘는 파일만 canvas로 JPEG 재인코딩해서, 화면 해상도는 그대로 두되 브리지로 나가는 바이트
    /// 수 자체를 줄이는지 확인한다.
    func testPastingALargeByteSizeImageIsReencodedToShrinkTheBridgePayload() async throws {
        final class DocCapturingWaiter: NSObject, EditorBridgeDelegate {
            var continuation: CheckedContinuation<Void, Never>?
            var lastDocument: EditorDocument?
            func editorBridgeDidBecomeReady(_ bridge: EditorBridge) {
                continuation?.resume()
                continuation = nil
            }
            func editorBridge(_ bridge: EditorBridge, didChangeDocument document: EditorDocument, plainText: String) {
                lastDocument = document
            }
            func editorBridge(_ bridge: EditorBridge, didChangeHeadings headings: [HeadingOutlineItem]) {}
            func editorBridge(_ bridge: EditorBridge, didChangeSelection selection: EditorSelectionState) {}
            func editorBridge(_ bridge: EditorBridge, didRequestOpenExternalLink url: URL) {}
        func editorBridge(_ bridge: EditorBridge, didRequestSaveAttachment payload: SaveAttachmentPayload) {}
        func editorBridge(_ bridge: EditorBridge, didRequestOpenAttachment payload: OpenAttachmentPayload) {}
            func editorBridge(_ bridge: EditorBridge, didReportError message: String) {}
        }

        let controller = RichEditorController()
        let waiter = DocCapturingWaiter()
        controller.delegate = waiter
        controller.setEditable(true)
        await withCheckedContinuation { continuation in waiter.continuation = continuation }
        controller.webView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)

        let pixelSize = 800
        let base64 = randomNoisePNGBase64(width: pixelSize, height: pixelSize)
        let originalByteCount = Data(base64Encoded: base64)?.count ?? 0
        XCTAssertGreaterThan(originalByteCount, 1_500_000, "테스트 전제: 원본 파일이 재인코딩 임계값보다 커야 한다")

        try await pasteImage(base64: base64, filename: "noise.png", into: controller)

        guard let size = try await waitForRenderedImageSize(in: controller) else {
            return XCTFail("큰 이미지가 삽입되지 않았다")
        }
        XCTAssertEqual(size.naturalWidth, Double(pixelSize), "재인코딩해도 픽셀 해상도는 원본과 같아야 한다(화질 저하 없이 전송 용량만 줄임)")

        let srcResult = try await controller.webView.evaluateJavaScript(
            "document.querySelector('#editor-root .ProseMirror img').getAttribute('src')"
        )
        guard let src = srcResult as? String else {
            return XCTFail("이미지 src를 읽을 수 없다")
        }
        XCTAssertTrue(
            src.hasPrefix("data:image/jpeg;base64,"),
            "임계값을 넘는 이미지는 JPEG로 재인코딩되어야 postMessage 브리지로 나가는 페이로드가 줄어든다"
        )

        try await Task.sleep(nanoseconds: 300_000_000)
        guard let document = waiter.lastDocument,
              let imageNode = document.content.first(where: { $0.type == "image" }),
              case .string(let savedSrc)? = imageNode.attrs?["src"] else {
            return XCTFail("docChanged로 넘어온 문서에서 image 노드를 찾을 수 없다")
        }
        XCTAssertLessThan(
            savedSrc.utf8.count, originalByteCount / 2,
            "재인코딩 후 실제로 저장·전송되는 바이트 수가 원본의 절반 미만으로 줄어야 한다 — 안 줄면 멈춤 버그가 재발한다"
        )
    }
}
