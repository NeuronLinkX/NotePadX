import XCTest
@testable import NotepadX

/// 테스트 클로저 안에서 플래그를 안전하게 뒤집기 위한 상자.
/// SaveCoordinator의 flush 클로저 타입이 `@Sendable`이라 평범한 `var` 캡처는
/// Swift 6 동시성 경고를 낸다 — 실제로는 MainActor에서 순차 실행되니 문제 없지만,
/// 경고를 없애기 위해 참조 타입 상자를 쓴다.
private final class Flag: @unchecked Sendable {
    var value = false
}

@MainActor
final class SaveCoordinatorTests: XCTestCase {
    /// 같은 노트를 여는 두 분할 패널이 서로 다른 등록 키를 쓰면, 종료 시 두 패널 모두 flush돼야 한다.
    /// (예전에는 note.id를 키로 써서 한쪽 등록이 다른 쪽을 덮어쓰는 버그가 있었다.)
    func testMultipleRegistrationsForSameLogicalNoteBothFlush() async {
        let coordinator = SaveCoordinator.shared
        let paneAFlushed = Flag()
        let paneBFlushed = Flag()

        let paneAID = UUID()
        let paneBID = UUID()

        coordinator.register(id: paneAID) { paneAFlushed.value = true }
        coordinator.register(id: paneBID) { paneBFlushed.value = true }

        await coordinator.flushAll()

        XCTAssertTrue(paneAFlushed.value)
        XCTAssertTrue(paneBFlushed.value)

        coordinator.unregister(id: paneAID)
        coordinator.unregister(id: paneBID)
    }

    func testUnregisterRemovesFlushClosure() async {
        let coordinator = SaveCoordinator.shared
        let flushed = Flag()
        let id = UUID()

        coordinator.register(id: id) { flushed.value = true }
        coordinator.unregister(id: id)
        await coordinator.flushAll()

        XCTAssertFalse(flushed.value)
    }
}
