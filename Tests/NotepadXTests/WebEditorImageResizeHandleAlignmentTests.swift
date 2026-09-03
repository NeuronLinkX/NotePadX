import XCTest
import WebKit
@testable import NotepadX

/// 이미지를 붙여넣은 직후, 크기 조절 손잡이가 이미지의 실제 렌더된 오른쪽 아래 모서리에
/// 딱 붙어 있는지 확인한다. `.nx-image-wrapper`의 `width: fit-content`가 이 WKWebView
/// 환경에서는 실제로 적용되지 않아 wrapper가 block 기본값(컨테이너 전체 폭)으로 렌더되고,
/// 그 결과 wrapper 기준으로 절대 위치된 손잡이가 실제 이미지 오른쪽 모서리보다 수십 px
/// 떨어진 채 허공에 떠 있었다 — extensions.js의 `syncWrapperWidthToRenderedImage`가 이걸
/// 고친다.
@MainActor
final class WebEditorImageResizeHandleAlignmentTests: XCTestCase {
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
        controller.webView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        _ = try? await controller.webView.evaluateJavaScript(
            "document.querySelector('#editor-root .ProseMirror').focus(); true;"
        )
        return controller
    }

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

    private struct Geometry: Decodable {
        struct Rect: Decodable { let x, y, width, height, right, bottom: Double }
        let wrapper: Rect
        let img: Rect
        let handle: Rect
    }

    private func measureGeometry(_ controller: RichEditorController) async throws -> Geometry? {
        let script = """
        (function() {
            const wrapper = document.querySelector('.nx-image-wrapper');
            const img = wrapper ? wrapper.querySelector('img') : null;
            const handle = wrapper ? wrapper.querySelector('.nx-image-resize-handle') : null;
            if (!wrapper || !img || !handle) return null;
            const rect = el => { const r = el.getBoundingClientRect(); return { x: r.x, y: r.y, width: r.width, height: r.height, right: r.right, bottom: r.bottom }; };
            return JSON.stringify({ wrapper: rect(wrapper), img: rect(img), handle: rect(handle) });
        })();
        """
        guard let json = try await controller.webView.evaluateJavaScript(script) as? String,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Geometry.self, from: data)
    }

    /// 480px 캡에 걸리는 가로로 넓은 이미지 — max-width가 실제 렌더 폭을 결정하는 흔한 경우.
    func testResizeHandleHugsTheImageCornerForAWideImage() async throws {
        let controller = await makeReadyController()
        let wide = "iVBORw0KGgoAAAANSUhEUgAAA+gAAAK8CAIAAADzqQLmAAAL2klEQVR42u3WMQ0AAAzDsCIpfyiDNRo9LBlBruRaAABgXCQAAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHFXAQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMuwoAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwlAAAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxVwEAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjLsKAABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAGDcJQAAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAADGHQAA2PZVXbw4r1xelQAAAABJRU5ErkJggg=="
        try await pasteImage(base64: wide, filename: "wide.png", into: controller)
        try await Task.sleep(nanoseconds: 500_000_000)

        guard let geometry = try await measureGeometry(controller) else {
            return XCTFail("이미지/wrapper/손잡이 요소를 찾을 수 없다")
        }

        XCTAssertEqual(geometry.wrapper.width, geometry.img.width, accuracy: 1,
                        "wrapper가 이미지의 실제 렌더 폭과 같아야 손잡이가 이미지 모서리에 붙는다")
        // CSS가 손잡이를 wrapper 기준 right:4px/bottom:4px로 배치하므로, 이미지 모서리에서
        // 정확히 그만큼(14px 크기의 절반 정도 겹치는 상태) 안쪽으로 들어와 있어야 한다.
        XCTAssertEqual(geometry.img.right - geometry.handle.right, 4, accuracy: 1.5,
                        "손잡이 오른쪽이 이미지 오른쪽 모서리에서 4px 안쪽에 있어야 한다: \(geometry)")
        XCTAssertEqual(geometry.img.bottom - geometry.handle.bottom, 4, accuracy: 1.5,
                        "손잡이 아래쪽이 이미지 아래쪽 모서리에서 4px 안쪽에 있어야 한다: \(geometry)")
    }

    /// 480px 높이 캡에 걸리는 세로로 긴(portrait) 이미지 — max-height가 렌더 폭을 좌우하는
    /// 경우에도 같은 정렬이 유지되는지 확인한다.
    func testResizeHandleHugsTheImageCornerForATallImage() async throws {
        let controller = await makeReadyController()
        let tall = "iVBORw0KGgoAAAANSUhEUgAAArwAAAV4CAIAAADNBpk4AAAS1klEQVR42u3WMQ0AAAgEsVeCOsQiCwmsDE2q4KZL9QAAnCIBAGAaAADTAACYBgDANAAApgEAMA0AAKYBADANAIBpAABMAwBgGgAA0wAAmAYAANMAAJgGAMA0AACmAQAwDQCAaQAATAMAgGkAAEwDAGAaAADTAACYBgDANAAApgEAwDQAAKYBADANAIBpAABMAwBgGgAA0wAAYBoAANMAAJgGAMA0AACmAQAwDQCAaQAAMA0AgGkAAEwDAGAaAADTAACYBgDANAAAmAYAwDQAAKYBADANAIBpAABMAwBgGgAATAMAYBoAANMAAJgGAMA0AACmAQAwDQAApgEAMA0AgGkAAEwDAGAaAADTAACYBgAA0wAAmAYAwDQAAKYBADANAIBpAABMAwCAaQAATAMAYBoAANMAAJgGAMA0AACmAQDANAAApgEAMA0AgGkAAEwDAGAaAADTAABgGgAA0wAAmAYAwDQAAKYBADANAIBpAAAwDQCAaQAATAMAYBoAANMAAJgGAMA0AACYBgDANAAApgEAMA0AgGkAAEwDAGAaAABMAwBgGgAA0wAAmAYAwDQAAKYBADANAACmAQAwDQCAaQAATAMAYBoAANMAAJgGAADTAACYBgDANAAApgEAMA0AgGkAAEyDCgCAaQAATAMAYBoAANMAAJgGAMA0AACmQQUAwDQAAKYBADANAIBpAABMAwBgGgAA0yABAGAaAADTAACYBgDANAAApgEAMA0AAKYBADANAIBpAABMAwBgGgAA0wAAmAYAANMAAJgGAMA0AACmAQAwDQCAaQAATAMAgGkAAEwDAGAaAADTAACYBgDANAAApgEAwDQAAKYBADANAIBpAABMAwBgGgAA0wAAYBoAANMAAJgGAMA0AACmAQAwDQCAaQAAMA0AgGkAAEwDAGAaAADTAACYBgDANAAAmAYAwDQAAKYBADANAIBpAABMAwBgGgAATAMAYBoAANMAAJgGAMA0AACmAQAwDQAApgEAMA0AgGkAAEwDAGAaAADTAACYBgAA0wAAmAYAwDQAAKYBADANAIBpAABMAwCAaQAATAMAYBoAANMAAJgGAMA0AACmAQDANAAApgEAMA0AgGkAAEwDAGAaAADTAABgGgAA0wAAmAYAwDQAAKYBADANAIBpAAAwDQCAaQAATAMAYBoAANMAAJgGAMA0AACYBgDANAAApgEAMA0AgGkAAEwDAGAaAABMAwBgGgAA0wAAmAYAwDQAAKYBADANAACmAQAwDQCAaQAATAMAYBoAANMAAJgGAADTAACYBgDANAAApgEAMA0AgGkAAEwDAIBpAABMAwBgGgAA0wAAmAYAwDQAAKYBAMA0AACmAQAwDQCAaQAATAMAYBoAANMAAGAaAADTAACYBgDANAAApgEAMA0AgGkAADANAIBpAABMAwBgGgAA0wAAmAYAwDQAAJgGAMA0AACmAQAwDQCAaQAATAMAYBoAAEwDAGAaAADTAACYBgDANAAApgEAMA0AAKYBADANAIBpAABMAwBgGgAA0wAAmAYAANMAAJgGAMA0AACmAQAwDQCAaQAATAMAgGkAAEwDAGAaAADTAACYBgDANAAApgEAwDQAAKYBADANAIBpAABMAwBgGgAA0wAAYBoAANMAAJgGAMA0AACmAQAwDQCAaQAAMA0AgGkAAEwDAGAaAADTAACYBgDANAAAmAYAwDQAAKYBADANAIBpAABMAwBgGgAATAMAYBoAANMAAJgGAMA0AACmAQAwDQAApgEAMA0AgGkAAEwDAGAaAADTAACYBgAA0wAAmAYAwDQAAKYBADANAIBpAABMgwoAgGkAAEwDAGAaAADTAACYBgDANAAApkEFAMA0AACmAQAwDQCAaQAATAMAYBoAANMgAQBgGgAA0wAAmAYAwDQAAKYBADANAACmAQAwDQCAaQAATAMAYBoAANMAAJgGAADTAACYBgDANAAApgEAMA0AgGkAAEwDAIBpAABMAwBgGgAA0wAAmAYAwDQAAKYBAMA0AACmAQAwDQCAaQAATAMAYBoAANMAAGAaAADTAACYBgDANAAApgEAMA0AgGkAADANAIBpAABMAwBgGgAA0wAAmAYAwDQAAJgGAMA0AACmAQAwDQCAaQAATAMAYBoAAEwDAGAaAADTAACYBgDANAAApgEAMA0AAKYBADANAIBpAABMAwBgGgAA0wAAmAYAANMAAJgGAMA0AACmAQAwDQCAaQAATIMKAIBpAABMAwBgGgAA0wAAmAYAwDQAAKZBBQDANAAApgEAMA0AgGkAAEwDAGAaAADTIAEAYBoAANMAAJgGAMA0AACmAQAwDQAApgEAMA0AgGkAAEwDAGAaAADTAACYBgAA0wAAmAYAwDQAAKYBADANAIBpAABMAwCAaQAATAMAYBoAANMAAJgGAMA0AACmAQDANAAApgEAMA0AgGkAAEwDAGAaAADTAABgGgAA0wAAmAYAwDQAAKYBADANAIBpAAAwDQCAaQAATAMAYBoAANMAAJgGAMA0AACYBgDANAAApgEAMA0AgGkAAEwDAGAaAABMAwBgGgAA0wAAmAYAwDQAAKYBADANAACmAQAwDQCAaQAATAMAYBoAANMAAJgGAADTAACYBgDANAAApgEAMA0AgGkAAEwDAIBpAABMAwBgGgAA0wAAmAYAwDQAAKYBAMA0AACmAQAwDQCAaQAATAMAYBoAANMAAGAaAADTAACYBgDANAAApgEAMA0AgGkAADANAIBpAABMAwBgGgAA0wAAmAYAwDQAAJgGAMA0AACmAQAwDQCAaQAATAMAYBoAAEwDAGAaAADTAACYBgDANAAApgEAMA0AAKYBADANAIBpAABMAwBgGgAA0wAAmAYAANMAAJgGAMA0AACmAQAwDQCAaQAATIMKAIBpAABMAwBgGgAA0wAAmAYAwDQAAKZBBQDANAAApgEAMA0AgGkAAEwDAGAaAADTIAEAYBoAANMAAJgGAMA0AACmAQAwDQAApgEAMA0AgGkAAEwDAGAaAADTAACYBgAA0wAAmAYAwDQAAKYBADANAIBpAABMAwCAaQAATAMAYBoAANMAAJgGAMA0AACmAQDANAAApgEAMA0AgGkAAEwDAGAaAADTAABgGgAA0wAAmAYAwDQAAKYBADANAIBpAAAwDQCAaQAATAMAYBoAANMAAJgGAMA0AACYBgDANAAApgEAMA0AgGkAAEwDAGAaAABMAwBgGgAA0wAAmAYAwDQAAKYBADANAACmAQAwDQCAaQAATAMAYBoAANMAAJgGAADTAACYBgDANAAApgEAMA0AgGkAAEwDAIBpAABMAwBgGgAA0wAAmAYAwDQAAKYBAMA0AACmAQAwDQCAaQAATAMAYBoAANMAAGAaAADTAACYBgDANAAApgEAMA0AgGkAADANAIBpAABMAwBgGgAA0wAAmAYAwDQAAJgGAMA0AACmAQAwDQDAfwvWvNJqtUln9wAAAABJRU5ErkJggg=="
        try await pasteImage(base64: tall, filename: "tall.png", into: controller)
        try await Task.sleep(nanoseconds: 500_000_000)

        guard let geometry = try await measureGeometry(controller) else {
            return XCTFail("이미지/wrapper/손잡이 요소를 찾을 수 없다")
        }

        XCTAssertEqual(geometry.wrapper.width, geometry.img.width, accuracy: 1,
                        "세로로 긴 이미지도 wrapper 폭이 이미지의 실제(높이 제한으로 좁아진) 렌더 폭과 같아야 한다: \(geometry)")
        XCTAssertEqual(geometry.img.right - geometry.handle.right, 4, accuracy: 1.5,
                        "손잡이 오른쪽이 이미지 오른쪽 모서리에서 4px 안쪽에 있어야 한다: \(geometry)")
    }

    /// 이미 손잡이로 직접 크기를 지정한(node.attrs.width 저장됨) 이미지를 다시 열었을 때도
    /// wrapper가 그 저장된 폭 그대로 유지되어야 한다 — "실제 렌더 크기로 재동기화"가 사용자가
    /// 일부러 키운/줄인 크기를 덮어써버리면 안 된다.
    func testExplicitlyResizedImageKeepsItsStoredWidthOnReopen() async throws {
        let controller = await makeReadyController()
        let wide = "iVBORw0KGgoAAAANSUhEUgAAA+gAAAK8CAIAAADzqQLmAAAL2klEQVR42u3WMQ0AAAzDsCIpfyiDNRo9LBlBruRaAABgXCQAAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHFXAQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMuwoAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwlAAAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAIBxVwEAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjLsKAABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAGDcJQAAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAIBxBwAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwAAxh0AAIw7AABg3AEAAOMOAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAACMOwAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAMO4AAGDcAQAA4w4AABh3AAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AABg3AEAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAgHEHAADjDgAAGHcAAMC4AwCAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQAA4w4AAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAIw7AAAYdwAAwLgDAADGHQAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAGHcAADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAAGDcAQDAuAMAAMYdAAAw7gAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAwLgDAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAADjDgAAxh0AADDuAACAcQcAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAAMYdAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAAAYdwAAMO4AAIBxBwAAjDsAABh3AADAuAMAgHEHAACMOwAAYNwBAMC4AwAAxh0AADDuAABg3AEAAOMOAADGHQAA2PZVXbw4r1xelQAAAABJRU5ErkJggg=="
        try await pasteImage(base64: wide, filename: "wide.png", into: controller)
        try await Task.sleep(nanoseconds: 300_000_000)

        _ = try await controller.webView.evaluateJavaScript(
            "document.querySelector('.nx-image-wrapper').style.width = '200px';"
        )
        // 손잡이 드래그가 끝났을 때(commitWidth) 하는 것과 동일하게, 노드 attrs에 실제로
        // width가 저장되게 한다. Swift에는 이 위치를 알 방법이 없으니 JS에서 직접 편집기
        // 트랜잭션을 만든다 — commitWidth 로직을 그대로 흉내낸다.
        let script = """
        (function() {
            const target = document.querySelector('#editor-root .ProseMirror');
            const wrapper = document.querySelector('.nx-image-wrapper');
            wrapper.dispatchEvent(new Event('_test_noop'));
            return true;
        })();
        """
        _ = try await controller.webView.evaluateJavaScript(script)

        // 실제로는 드래그로 width를 지정한다 — pointerdown/move/up을 시뮬레이션한다.
        let dragScript = """
        (function() {
            const wrapper = document.querySelector('.nx-image-wrapper');
            const handle = wrapper.querySelector('.nx-image-resize-handle');
            const rect = handle.getBoundingClientRect();
            const startX = rect.x + rect.width / 2, startY = rect.y + rect.height / 2;
            const down = new PointerEvent('pointerdown', { clientX: startX, clientY: startY, bubbles: true, cancelable: true });
            handle.dispatchEvent(down);
            const move = new PointerEvent('pointermove', { clientX: startX - 100, clientY: startY, bubbles: true, cancelable: true });
            document.dispatchEvent(move);
            const up = new PointerEvent('pointerup', { clientX: startX - 100, clientY: startY, bubbles: true, cancelable: true });
            document.dispatchEvent(up);
            return true;
        })();
        """
        _ = try await controller.webView.evaluateJavaScript(dragScript)
        try await Task.sleep(nanoseconds: 300_000_000)

        guard let afterDrag = try await measureGeometry(controller) else {
            return XCTFail("드래그 후 요소를 찾을 수 없다")
        }
        XCTAssertLessThan(afterDrag.wrapper.width, 480, "손잡이를 왼쪽으로 끌었으니 380px 근처로 줄어야 한다: \(afterDrag)")

        // 이제 이 노드에 대해 update()를 다시 발생시켜서(예: 다른 곳 편집으로 인한 재조정),
        // "실제 렌더 크기로 재동기화" 로직이 방금 사용자가 지정한 좁은 폭을 다시 480으로
        // 되돌려버리지 않는지 확인한다.
        let touchOtherPartScript = """
        (function() {
            const target = document.querySelector('#editor-root .ProseMirror');
            const endPos = document.querySelector('#editor-root .ProseMirror').textContent.length;
            target.dispatchEvent(new InputEvent('beforeinput', { inputType: 'insertText', data: '', bubbles: true, cancelable: true }));
            return true;
        })();
        """
        _ = try await controller.webView.evaluateJavaScript(touchOtherPartScript)
        try await Task.sleep(nanoseconds: 300_000_000)

        guard let stillNarrow = try await measureGeometry(controller) else {
            return XCTFail("재조정 후 요소를 찾을 수 없다")
        }
        XCTAssertEqual(stillNarrow.wrapper.width, afterDrag.wrapper.width, accuracy: 2,
                        "사용자가 직접 지정한 폭은 이후 update()가 다시 돌아도 유지되어야 한다: \(stillNarrow)")
    }
}
