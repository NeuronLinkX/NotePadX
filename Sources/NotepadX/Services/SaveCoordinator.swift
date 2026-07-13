import Foundation

/// 현재 편집 중인 노트들의 "지금 바로 저장" 클로저를 등록해 두었다가
/// 앱 비활성화/종료 시 한꺼번에 flush한다. AppDelegate와 EditorViewModel 사이의
/// 결합을 없애기 위한 얇은 중재자.
@MainActor
final class SaveCoordinator {
    static let shared = SaveCoordinator()

    private var pendingFlushes: [UUID: @Sendable () async -> Void] = [:]

    private init() {}

    func register(id: UUID, flush: @escaping @Sendable () async -> Void) {
        pendingFlushes[id] = flush
    }

    func unregister(id: UUID) {
        pendingFlushes.removeValue(forKey: id)
    }

    func flushAll() async {
        for flush in pendingFlushes.values {
            await flush()
        }
    }
}
