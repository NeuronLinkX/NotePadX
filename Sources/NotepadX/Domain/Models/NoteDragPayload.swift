import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// 메모 목록 → 사이드바 폴더 드래그 앤 드롭 전용 타입. Info.plist의
    /// `UTExportedTypeDeclarations`에도 같은 식별자로 정식 선언되어 있다 — 실제 드래그
    /// 세션은 프로세스 안에서 시작해도 시스템 pasteboard 서버를 거치므로, 코드에서만
    /// 즉석으로 만든 타입은 그 왕복 과정에서 사라질 수 있다.
    static var notepadXNoteIDs: UTType {
        UTType("com.notepadx.app.note-id-list") ?? UTType(exportedAs: "com.notepadx.app.note-id-list")
    }
}

/// 메모 목록에서 사이드바 폴더로 드래그 앤 드롭할 때 옮겨지는 페이로드. 노트 전체(리치 텍스트
/// 본문 JSON 포함)가 아니라 id만 담아서, 드래그를 시작하는 순간 문서 내용을 통째로
/// 직렬화하지 않는다.
///
/// `NSItemProvider` 기반 `onDrag`/`onDrop`으로 옮긴다 — 더 새로운 `Transferable`/
/// `.draggable`/`.dropDestination` 조합을 먼저 썼지만 실제 기기에서 드롭이 인식되지 않는
/// 경우가 있어(macOS List 행 사이·NavigationSplitView 컬럼을 넘나드는 드래그에서 알려진
/// 문제), 오래 검증된 API로 바꿨다.
struct NoteDragPayload: Codable {
    let noteIDs: [UUID]

    func makeItemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        guard let data = try? JSONEncoder().encode(self) else { return provider }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.notepadXNoteIDs.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    /// 드롭된 `NSItemProvider` 목록에서 이 페이로드들을 비동기로 복원한다. `onCompletion`은
    /// 메인 스레드에서 호출된다 — `loadDataRepresentation`의 콜백 자체는 백그라운드 큐에서
    /// 오므로, 이 안에서 바로 `@Published` 상태를 건드리면 안 된다.
    static func loadAll(from providers: [NSItemProvider], onCompletion: @escaping (Set<UUID>) -> Void) {
        let typeIdentifier = UTType.notepadXNoteIDs.identifier
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(typeIdentifier) }
        guard !matching.isEmpty else { return }

        let group = DispatchGroup()
        var collectedIDs = Set<UUID>()
        let lock = NSLock()

        for provider in matching {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                defer { group.leave() }
                guard let data, let payload = try? JSONDecoder().decode(NoteDragPayload.self, from: data) else { return }
                lock.lock()
                collectedIDs.formUnion(payload.noteIDs)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            guard !collectedIDs.isEmpty else { return }
            onCompletion(collectedIDs)
        }
    }
}
