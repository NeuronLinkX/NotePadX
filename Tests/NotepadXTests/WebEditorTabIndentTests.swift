import XCTest
import WebKit
@testable import NotepadX

/// Tab 키로 목록 항목을 들여쓰는 동작을 검증한다. ListItem 확장의 기본 Tab 키맵은
/// `sinkListItem`이 적용될 수 없는 선택(예: 옮겨 붙일 이전 형제가 없는 목록의 첫 항목)이면
/// 조용히 실패하고, 그러면 ProseMirror가 그 keydown을 "처리 안 됨"으로 보고 흘려보내
/// WKWebView가 표준 포커스 이동(예: 검색창으로 이동)으로 받아들이는 버그가 있었다.
/// editor.js의 handleKeyDown이 Tab을 항상 가로채 preventDefault하도록 고쳤으므로, 그
/// 두 경우(들여쓰기 성공 / 실패) 모두를 실제 keydown 이벤트로 확인한다.
@MainActor
final class WebEditorTabIndentTests: XCTestCase {
    private final class ReadyWaiter: NSObject, EditorBridgeDelegate {
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

    private func makeReadyController() async -> (RichEditorController, ReadyWaiter) {
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

    /// 커서를 문서 끝(마지막 글자 뒤)에 두고 Tab을 dispatch한다. 실제 dispatchEvent의
    /// 반환값으로 preventDefault 여부를 그대로 읽는다 — false면 취소(=처리)됐다는 뜻이다.
    private func dispatchTabAtEnd(shiftKey: Bool, into controller: RichEditorController) async throws -> Bool {
        let script = """
        (function() {
            const target = document.querySelector('#editor-root .ProseMirror');
            target.focus();
            const selection = window.getSelection();
            const range = document.createRange();
            range.selectNodeContents(target);
            range.collapse(false);
            selection.removeAllRanges();
            selection.addRange(range);
            const event = new KeyboardEvent('keydown', { key: 'Tab', shiftKey: \(shiftKey), bubbles: true, cancelable: true });
            const notPrevented = target.dispatchEvent(event);
            return notPrevented;
        })();
        """
        let result = try await controller.webView.evaluateJavaScript(script)
        try await Task.sleep(nanoseconds: 250_000_000)
        return (result as? Bool) ?? true
    }

    func testTabIndentsSecondListItemUnderTheFirst() async throws {
        let (controller, waiter) = await makeReadyController()
        try await pastePlainText("- 항목1\n- 항목2", into: controller)

        let notPrevented = try await dispatchTabAtEnd(shiftKey: false, into: controller)

        XCTAssertFalse(notPrevented, "Tab은 항상 preventDefault되어 편집기 밖으로 포커스가 나가면 안 된다")
        guard let document = waiter.lastDocument else {
            return XCTFail("Tab 이후 docChanged로 문서가 넘어오지 않았다")
        }
        // 두 번째 항목이 첫 번째 항목 밑에 중첩된 하위 목록으로 들어갔는지 확인한다.
        guard let topList = document.content.first(where: { $0.type == "bulletList" }),
              let firstItem = topList.content?.first else {
            return XCTFail("최상위 불릿 목록을 찾을 수 없다: \(document)")
        }
        let hasNestedList = (firstItem.content ?? []).contains { $0.type == "bulletList" }
        XCTAssertTrue(hasNestedList, "들여쓰기 후 두 번째 항목이 첫 번째 항목의 하위 목록이 되어야 한다")
    }

    /// 목록의 첫 항목(옮겨 붙일 이전 형제가 없음)에서 Tab을 누르면 sinkListItem 자체는
    /// 실패하지만, 그래도 keydown은 편집기가 계속 처리해서(preventDefault) 포커스가
    /// 검색창 같은 다른 곳으로 튀지 않아야 한다 — 이게 실제로 보고된 버그였다.
    func testTabOnFirstListItemStaysPreventedEvenWhenSinkIsImpossible() async throws {
        let (controller, _) = await makeReadyController()
        try await pastePlainText("- 유일한 항목", into: controller)

        let notPrevented = try await dispatchTabAtEnd(shiftKey: false, into: controller)

        XCTAssertFalse(notPrevented, "들여쓸 대상이 없어 sinkListItem이 실패하더라도 Tab keydown은 여전히 편집기가 소비해야 한다(포커스가 검색창으로 새지 않아야 한다)")
    }

    /// 실제 사용자가 보고한 시나리오: 세 번째 항목까지 마우스로 드래그해 선택한(캐럿이 아니라
    /// 범위 선택) 상태에서 Tab을 누른다. 첫 항목("용어 정의")을 제외한 나머지 두 항목이
    /// 모두 그 아래로 들여써져야 한다.
    ///
    /// 선택(Range 설정)과 Tab keydown을 별도의 evaluateJavaScript 호출로 나눈다 — 실제
    /// 사용자는 마우스를 놓고 나서(드래그 종료) 손을 키보드로 옮겨 Tab을 누르기까지 시간이
    /// 걸리지만, 같은 스크립트 안에서 연달아 실행하면 ProseMirror가 `selectionchange`를 통해
    /// 브라우저 네이티브 선택을 자신의 상태로 동기화하기 전에 keydown이 가로채여, 오래된(이전)
    /// 선택 기준으로 들여쓰기가 계산되는 레이스가 생길 수 있다.
    private func selectAcrossTwoListItems(into controller: RichEditorController) async throws {
        let script = """
        (function() {
            const target = document.querySelector('#editor-root .ProseMirror');
            target.focus();
            const items = target.querySelectorAll('li');
            const secondText = items[1].querySelector('p') || items[1];
            const thirdText = items[2].querySelector('p') || items[2];
            const range = document.createRange();
            range.setStart(secondText.firstChild || secondText, 0);
            const endNode = thirdText.lastChild || thirdText;
            const endOffset = endNode.nodeType === Node.TEXT_NODE ? endNode.textContent.length : 0;
            range.setEnd(endNode, endOffset);
            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
            return true;
        })();
        """
        _ = try await controller.webView.evaluateJavaScript(script)
        try await Task.sleep(nanoseconds: 150_000_000)
    }

    private func dispatchTabOnFocusedEditor(into controller: RichEditorController) async throws -> Bool {
        let script = """
        (function() {
            const target = document.querySelector('#editor-root .ProseMirror');
            const event = new KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true });
            return target.dispatchEvent(event);
        })();
        """
        let result = try await controller.webView.evaluateJavaScript(script)
        try await Task.sleep(nanoseconds: 250_000_000)
        return (result as? Bool) ?? true
    }

    func testTabIndentsMultipleDragSelectedListItemsTogether() async throws {
        let (controller, waiter) = await makeReadyController()
        try await pastePlainText("- 용어 정의\n- 규범이라는 용어\n- 체인이라는 용어", into: controller)
        try await selectAcrossTwoListItems(into: controller)

        let notPrevented = try await dispatchTabOnFocusedEditor(into: controller)

        XCTAssertFalse(notPrevented, "여러 항목에 걸친 드래그 선택에서도 Tab은 편집기가 소비해야 한다")
        guard let document = waiter.lastDocument else {
            return XCTFail("Tab 이후 docChanged로 문서가 넘어오지 않았다")
        }
        guard let topList = document.content.first(where: { $0.type == "bulletList" }) else {
            return XCTFail("최상위 불릿 목록을 찾을 수 없다: \(document)")
        }
        XCTAssertEqual(topList.content?.count, 1, "세 항목이 모두 첫 항목 밑으로 들어가서, 최상위 목록에는 첫 항목 하나만 남아야 한다: \(document)")
        let firstItem = topList.content?.first
        let nestedList = firstItem?.content?.first { $0.type == "bulletList" }
        XCTAssertEqual(nestedList?.content?.count, 2, "드래그로 선택했던 두 항목이 함께 하위 목록으로 들어가야 한다: \(document)")
    }

    /// 위 테스트보다 더 가혹한 경우: 드래그로 선택을 끝낸 "직후" 곧바로 Tab을 누른다(선택 설정과
    /// keydown을 같은 스크립트 실행 한 번에 몰아서, 인위적으로 최악의 타이밍을 만든다). 실제
    /// 사용자가 겪은 "선택하고 Tab을 눌렀는데 아무 일도 안 일어난다"는 버그가 정확히 이런
    /// selectionchange 동기화 레이스 때문이었다 — handleKeyDown의 syncSelectionFromBrowser가
    /// 이 경우에도 올바르게 동작해야 한다.
    func testTabIndentsMultipleDragSelectedListItemsEvenWithoutSyncDelay() async throws {
        let (controller, waiter) = await makeReadyController()
        try await pastePlainText("- 용어 정의\n- 규범이라는 용어\n- 체인이라는 용어", into: controller)

        let script = """
        (function() {
            const target = document.querySelector('#editor-root .ProseMirror');
            target.focus();
            const items = target.querySelectorAll('li');
            const secondText = items[1].querySelector('p') || items[1];
            const thirdText = items[2].querySelector('p') || items[2];
            const range = document.createRange();
            range.setStart(secondText.firstChild || secondText, 0);
            const endNode = thirdText.lastChild || thirdText;
            const endOffset = endNode.nodeType === Node.TEXT_NODE ? endNode.textContent.length : 0;
            range.setEnd(endNode, endOffset);
            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
            const event = new KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true });
            return target.dispatchEvent(event);
        })();
        """
        let result = try await controller.webView.evaluateJavaScript(script)
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(result as? Bool, false, "레이스 상황이어도 Tab은 여전히 편집기가 소비해야 한다")
        guard let document = waiter.lastDocument,
              let topList = document.content.first(where: { $0.type == "bulletList" }) else {
            return XCTFail("Tab 이후 docChanged로 최상위 불릿 목록을 찾을 수 없다")
        }
        XCTAssertEqual(topList.content?.count, 1, "selectionchange 동기화가 아직 안 끝난 상태에서 Tab을 눌러도 방금 만든 선택 기준으로 들여써져야 한다: \(document)")
    }
}
