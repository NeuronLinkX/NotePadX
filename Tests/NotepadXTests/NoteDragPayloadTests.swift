import XCTest
@testable import NotepadX

/// `NoteDragPayload`가 실제 `NSItemProvider`를 거쳐 왕복하는지 검증한다 — 메모 목록 →
/// 사이드바 폴더 드래그 앤 드롭이 SwiftUI 뷰 레이어가 아니라 이 인코딩/디코딩 단계에서
/// 깨졌던 적이 있어서(예: 잘못된 타입 식별자), 뷰와 분리해서 이 부분만 직접 확인한다.
final class NoteDragPayloadTests: XCTestCase {
    func testItemProviderRoundTripsNoteIDs() throws {
        let ids = [UUID(), UUID()]
        let provider = NoteDragPayload(noteIDs: ids).makeItemProvider()

        let expectation = expectation(description: "loadAll")
        var received: Set<UUID> = []
        NoteDragPayload.loadAll(from: [provider]) { decoded in
            received = decoded
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(received, Set(ids))
    }

    func testLoadAllMergesMultipleProvidersIntoOneSet() throws {
        let first = NoteDragPayload(noteIDs: [UUID()]).makeItemProvider()
        let secondID = UUID()
        let second = NoteDragPayload(noteIDs: [secondID]).makeItemProvider()

        let expectation = expectation(description: "loadAll")
        var received: Set<UUID> = []
        NoteDragPayload.loadAll(from: [first, second]) { decoded in
            received = decoded
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(received.count, 2)
        XCTAssertTrue(received.contains(secondID))
    }

    func testLoadAllIgnoresProvidersOfUnrelatedType() {
        let unrelated = NSItemProvider(object: "plain text" as NSString)

        var didCallCompletion = false
        NoteDragPayload.loadAll(from: [unrelated]) { _ in didCallCompletion = true }

        // 콜백은 비동기이므로, "안 불렸다"를 확정하려면 짧게 기다렸다가 확인한다.
        let expectation = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)

        XCTAssertFalse(didCallCompletion, "관련 없는 타입의 provider만 있으면 콜백이 아예 호출되면 안 된다")
    }
}
