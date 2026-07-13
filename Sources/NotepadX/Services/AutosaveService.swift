import Foundation

/// 편집 중 500~800ms debounce로 자동 저장하고, 창이 닫히거나 앱이 비활성화될 때는
/// `flush`로 대기 중인 저장을 즉시 실행한다 (스펙 10절).
@MainActor
final class AutosaveService {
    private var pendingTask: Task<Void, Never>?
    private let debounceNanoseconds: UInt64
    private let onSave: @Sendable (Note) async -> Void
    private(set) var lastSaveError: AppError?

    init(debounceMilliseconds: UInt64 = 600, onSave: @escaping @Sendable (Note) async -> Void) {
        self.debounceNanoseconds = debounceMilliseconds * 1_000_000
        self.onSave = onSave
    }

    /// 편집 이벤트마다 호출한다. 이전에 대기 중이던 저장은 취소되고 새 타이머가 시작된다.
    func scheduleSave(_ note: Note) {
        pendingTask?.cancel()
        let debounceNanoseconds = self.debounceNanoseconds
        let onSave = self.onSave
        pendingTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await onSave(note)
        }
    }

    /// 대기 중인 자동 저장을 취소하고 즉시 저장한다.
    func flush(_ note: Note) async {
        pendingTask?.cancel()
        pendingTask = nil
        await onSave(note)
    }

    func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}
