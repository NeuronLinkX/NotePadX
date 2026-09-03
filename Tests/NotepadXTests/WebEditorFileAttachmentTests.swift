import XCTest
import WebKit
@testable import NotepadX

/// 이미지가 아닌 파일(엑셀·PDF·한글·워드 등)을 드래그·붙여넣기하면 실제로 fileAttachment
/// 노드가 만들어지고, Swift로 saveAttachment 브리지 메시지가 나가고, 카드를 클릭하면
/// openAttachment가 같은 id로 돌아오는지 실제 WKWebView + paste 이벤트로 검증한다.
@MainActor
final class WebEditorFileAttachmentTests: XCTestCase {
    private final class Waiter: NSObject, EditorBridgeDelegate {
        var continuation: CheckedContinuation<Void, Never>?
        var lastDocument: EditorDocument?
        var savedAttachments: [SaveAttachmentPayload] = []
        var openedAttachments: [OpenAttachmentPayload] = []
        var errors: [String] = []

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
        func editorBridge(_ bridge: EditorBridge, didRequestSaveAttachment payload: SaveAttachmentPayload) {
            savedAttachments.append(payload)
        }
        func editorBridge(_ bridge: EditorBridge, didRequestOpenAttachment payload: OpenAttachmentPayload) {
            openedAttachments.append(payload)
        }
        func editorBridge(_ bridge: EditorBridge, didReportError message: String) {
            errors.append(message)
        }
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

    /// 클립보드 파일 붙여넣기를 실제 paste 이벤트로 흉내낸다(이미지 붙여넣기 테스트와 같은 패턴).
    private func pasteFile(base64: String, filename: String, mimeType: String, into controller: RichEditorController) async throws {
        let script = """
        (function() {
            const base64 = '\(base64)';
            const byteChars = atob(base64);
            const bytes = new Uint8Array(byteChars.length);
            for (let i = 0; i < byteChars.length; i++) bytes[i] = byteChars.charCodeAt(i);
            const file = new File([bytes], '\(filename)', { type: '\(mimeType)' });
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
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    // 아주 작은 임의 바이트 — 실제 유효한 xlsx/pdf일 필요는 없다(형식을 열어보지 않으므로).
    private let tinyPayload = Data("not a real spreadsheet, just bytes".utf8).base64EncodedString()

    func testPastingExcelFileInsertsAttachmentAndSavesBytes() async throws {
        let (controller, waiter) = await makeReadyController()
        try await pasteFile(
            base64: tinyPayload,
            filename: "연간 실적.xlsx",
            mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            into: controller
        )

        guard let document = waiter.lastDocument,
              let node = document.content.first(where: { $0.type == "fileAttachment" }) else {
            return XCTFail("fileAttachment 노드가 문서에 들어가지 않았다: \(String(describing: waiter.lastDocument))")
        }
        guard case .string(let fileName)? = node.attrs?["fileName"] else {
            return XCTFail("fileName 속성이 없다: \(node)")
        }
        XCTAssertEqual(fileName, "연간 실적.xlsx")

        XCTAssertEqual(waiter.savedAttachments.count, 1)
        let saved = try XCTUnwrap(waiter.savedAttachments.first)
        XCTAssertEqual(saved.fileName, "연간 실적.xlsx")
        XCTAssertEqual(Data(base64Encoded: saved.base64Data), Data(base64Encoded: tinyPayload))
        // 문서에 넣은 attachmentId와 Swift로 보낸 saveAttachment의 attachmentId가 같아야
        // 나중에 클릭했을 때 같은 파일을 찾을 수 있다.
        if case .string(let attachmentId)? = node.attrs?["attachmentId"] {
            XCTAssertEqual(attachmentId, saved.attachmentId)
        } else {
            XCTFail("attachmentId 속성이 없다: \(node)")
        }
    }

    func testClickingAttachmentCardRequestsOpenWithMatchingId() async throws {
        let (controller, waiter) = await makeReadyController()
        try await pasteFile(base64: tinyPayload, filename: "보고서.pdf", mimeType: "application/pdf", into: controller)
        guard let saved = waiter.savedAttachments.first else {
            return XCTFail("saveAttachment이 호출되지 않았다")
        }

        _ = try await controller.webView.evaluateJavaScript(
            "document.querySelector('.nx-file-attachment').click(); true;"
        )
        try await Task.sleep(nanoseconds: 200_000_000)

        guard let opened = waiter.openedAttachments.first else {
            return XCTFail("첨부파일 카드를 클릭해도 openAttachment가 호출되지 않았다")
        }
        XCTAssertEqual(opened.attachmentId, saved.attachmentId)
        XCTAssertEqual(opened.fileName, "보고서.pdf")
    }

    /// 파일 종류별로 다른 라벨(SVG 안의 텍스트)이 붙는지 — PDF/한글(HWP)/Word/Excel이
    /// 서로 구분되게 나와야 한다는 요청을 검증한다.
    func testAttachmentIconLabelDiffersByFileType() async throws {
        let cases: [(filename: String, mimeType: String, expectedLabel: String)] = [
            ("문서.hwp", "application/x-hwp", "한글"),
            ("문서.pdf", "application/pdf", "PDF"),
            ("문서.docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "DOC"),
            ("문서.xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "XLS"),
        ]

        for testCase in cases {
            let (controller, _) = await makeReadyController()
            try await pasteFile(base64: tinyPayload, filename: testCase.filename, mimeType: testCase.mimeType, into: controller)

            let label = try await controller.webView.evaluateJavaScript(
                "document.querySelector('.nx-file-attachment-icon svg text') ? document.querySelector('.nx-file-attachment-icon svg text').textContent : null"
            ) as? String
            XCTAssertEqual(label, testCase.expectedLabel, "\(testCase.filename)의 아이콘 라벨이 기대와 다르다")
        }
    }

    func testOversizedFileIsRejectedWithErrorAndNotInserted() async throws {
        let (controller, waiter) = await makeReadyController()
        // 20MB 캡을 넘는 파일임을 흉내낸다 — 실제 21MB 바이트를 만들 필요 없이 File 생성자에
        // 넘기는 배열 길이로 크기를 흉내낼 수 있다.
        let script = """
        (function() {
            const bigBytes = new Uint8Array(21 * 1024 * 1024);
            const file = new File([bigBytes], 'huge.zip', { type: 'application/zip' });
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
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(waiter.savedAttachments.isEmpty, "20MB 넘는 파일은 저장 요청 자체가 안 나가야 한다")
        XCTAssertFalse(waiter.errors.isEmpty, "20MB 넘는 파일을 붙여넣으면 오류 메시지가 와야 한다")
    }

    /// 크기만 흉내낸 게 아니라 실제 ~18MB 바이트를 끝까지(FileReader → base64 인코딩 →
    /// WKScriptMessageHandler로 postMessage → Swift 디코딩) 왕복시켜서, 캡을 20MB로 올린 게
    /// 실제로 큰 한글(HWP) 파일 같은 걸 진짜로 옮길 수 있는지 확인한다. 이 브리지가 큰 단일
    /// 문자열 페이로드에 취약했던 전례(REENCODE_THRESHOLD_BYTES 주석 참고)가 있어서, 크기
    /// 시뮬레이션만으로는 부족하고 실제 바이트를 흘려보내 봐야 한다.
    func testLargeAttachmentUpTo20MBRoundTripsSuccessfully() async throws {
        let (controller, waiter) = await makeReadyController()
        let sizeMB = 18
        let script = """
        (function() {
            const bytes = new Uint8Array(\(sizeMB) * 1024 * 1024).fill(65);
            const file = new File([bytes], '대용량 한글파일.hwp', { type: 'application/x-hwp' });
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
        // 18MB base64 인코딩·전송은 자잘한 첨부보다 오래 걸리니 여유 있게 기다린다.
        try await Task.sleep(nanoseconds: 3_000_000_000)

        XCTAssertTrue(waiter.errors.isEmpty, "20MB 이하 파일은 오류 없이 저장되어야 한다: \(waiter.errors)")
        guard let saved = waiter.savedAttachments.first else {
            return XCTFail("18MB 파일에 대해 saveAttachment가 호출되지 않았다")
        }
        XCTAssertEqual(saved.fileName, "대용량 한글파일.hwp")
        let decoded = try XCTUnwrap(Data(base64Encoded: saved.base64Data))
        XCTAssertEqual(decoded.count, sizeMB * 1024 * 1024, "왕복한 바이트 수가 원본과 달라 잘리거나 손상됐을 수 있다")
    }
}
