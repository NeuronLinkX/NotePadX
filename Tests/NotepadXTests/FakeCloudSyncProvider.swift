import Foundation
@testable import NotepadX

/// OneDriveSyncUseCase의 충돌 감지 로직을 파일시스템이나 네트워크 없이 테스트하기 위한
/// 메모리 기반 CloudSyncProvider. actor로 만들어 동시 접근에도 안전하다.
actor FakeCloudSyncProvider: CloudSyncProvider {
    private var storage: [String: SyncDocument] = [:]

    func seed(_ document: SyncDocument) {
        storage[document.noteID.uuidString] = document
    }

    func authenticate() async throws {}
    func signOut() async throws { storage.removeAll() }

    func listNotes() async throws -> [RemoteNote] {
        storage.values.map { RemoteNote(id: $0.noteID.uuidString, title: $0.title, updatedAt: $0.updatedAt, contentHash: $0.contentHash) }
    }

    func upload(_ note: SyncDocument) async throws {
        storage[note.noteID.uuidString] = note
    }

    func download(id: String) async throws -> SyncDocument {
        guard let document = storage[id] else { throw SyncProviderError.notFound }
        return document
    }

    func delete(id: String) async throws {
        storage.removeValue(forKey: id)
    }
}
