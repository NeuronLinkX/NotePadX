import Foundation

/// 스펙 13절: 로컬과 원격을 마지막 동기화 시점(base)과 비교해 어느 쪽이 바뀌었는지 판단하고,
/// 양쪽 다 바뀌었을 때만 충돌로 표시한다. 절대 자동으로 한쪽을 덮어쓰지 않는다.
struct OneDriveSyncUseCase: Sendable {
    private let noteRepository: any NoteRepository
    private let syncStateRepository: any SyncStateRepository
    private let searchIndex: SearchIndexService
    let deviceID: String

    init(
        noteRepository: any NoteRepository,
        syncStateRepository: any SyncStateRepository,
        searchIndex: SearchIndexService,
        deviceID: String
    ) {
        self.noteRepository = noteRepository
        self.syncStateRepository = syncStateRepository
        self.searchIndex = searchIndex
        self.deviceID = deviceID
    }

    func sync(noteID: UUID, using provider: any CloudSyncProvider) async throws -> SyncOutcome {
        guard let note = try await noteRepository.fetchNote(id: noteID) else {
            throw AppError.documentCorrupted
        }
        let syncState = try await syncStateRepository.syncState(forNote: noteID)
        let baseHash = syncState?.lastSyncedContentHash

        let remote: SyncDocument?
        do {
            remote = try await provider.download(id: noteID.uuidString)
        } catch SyncProviderError.notFound {
            remote = nil
        }

        guard let remote else {
            try await push(note: note, baseHash: baseHash, provider: provider)
            return .uploaded
        }

        let localChanged = baseHash != note.contentHash
        let remoteChanged = baseHash != remote.contentHash

        switch (localChanged, remoteChanged) {
        case (false, false):
            return .upToDate

        case (true, false):
            try await push(note: note, baseHash: baseHash, provider: provider)
            return .uploaded

        case (false, true):
            try await pull(remote: remote, noteID: noteID, provider: provider)
            return .downloaded

        case (true, true):
            if note.contentHash == remote.contentHash {
                // 둘 다 바뀌었지만 결과 내용이 같다 (예: 같은 편집이 두 기기에서 독립적으로 반영됨) — 충돌 아님.
                try await recordSyncState(noteID: noteID, contentHash: note.contentHash, updatedAt: note.updatedAt)
                return .upToDate
            }
            return .conflict(SyncConflict(
                noteID: noteID,
                localTitle: note.title,
                localPlainText: note.plainText,
                localUpdatedAt: note.updatedAt,
                remoteTitle: remote.title,
                remotePlainText: remote.plainText,
                remoteUpdatedAt: remote.updatedAt
            ))
        }
    }

    /// 충돌 해결. .keepBoth는 원격 버전을 별도 노트로 복제해 두 버전 다 잃지 않게 한다.
    func resolveConflict(
        _ conflict: SyncConflict,
        resolution: SyncConflictResolution,
        using provider: any CloudSyncProvider
    ) async throws {
        switch resolution {
        case .keepLocal:
            guard let note = try await noteRepository.fetchNote(id: conflict.noteID) else { return }
            try await push(note: note, baseHash: nil, provider: provider, forceOverwriteRemote: true)

        case .keepRemote:
            let remote = try await provider.download(id: conflict.noteID.uuidString)
            try await pull(remote: remote, noteID: conflict.noteID, provider: provider)

        case .keepBoth:
            guard let localNote = try await noteRepository.fetchNote(id: conflict.noteID) else { return }
            let remote = try await provider.download(id: conflict.noteID.uuidString)
            let remoteDocument = (try? EditorDocument.decode(from: remote.documentJSON)) ?? .fromPlainText(remote.plainText)
            let duplicated = Note(
                folderID: localNote.folderID,
                title: remote.title + " (원격 버전)",
                documentJSON: try remoteDocument.encoded(),
                plainText: remote.plainText,
                source: .oneDrive,
                contentHash: NoteUseCase.contentHash(for: remote.plainText),
                syncState: .synced
            )
            try await noteRepository.createNote(duplicated)
            try await searchIndex.reindexNote(id: duplicated.id)
            // 로컬 노트는 그대로 유지하고, 그 위치를 새 기준점으로 다시 업로드해 다음 동기화가 다시
            // 충돌로 뜨지 않게 한다.
            try await push(note: localNote, baseHash: nil, provider: provider, forceOverwriteRemote: true)
        }
    }

    private func push(note: Note, baseHash: String?, provider: any CloudSyncProvider, forceOverwriteRemote: Bool = false) async throws {
        let document = SyncDocument(
            noteID: note.id,
            title: note.title,
            documentJSON: note.documentJSON,
            plainText: note.plainText,
            updatedAt: note.updatedAt,
            contentHash: note.contentHash,
            baseRevision: baseHash,
            deviceID: deviceID
        )
        try await provider.upload(document)
        try await recordSyncState(noteID: note.id, contentHash: note.contentHash, updatedAt: note.updatedAt)
        try await noteRepository.updateNote(withSyncState(note, .synced))
    }

    private func pull(remote: SyncDocument, noteID: UUID, provider: any CloudSyncProvider) async throws {
        guard var local = try await noteRepository.fetchNote(id: noteID) else { return }
        let document = (try? EditorDocument.decode(from: remote.documentJSON)) ?? .fromPlainText(remote.plainText)
        local.title = remote.title
        local.documentJSON = try document.encoded()
        local.plainText = remote.plainText
        local.contentHash = remote.contentHash
        local.updatedAt = remote.updatedAt
        local.source = .oneDrive
        local.syncState = .synced
        try await noteRepository.updateNote(local)
        try await searchIndex.reindexNote(id: noteID)
        try await recordSyncState(noteID: noteID, contentHash: remote.contentHash, updatedAt: remote.updatedAt)
    }

    private func withSyncState(_ note: Note, _ state: SyncState) -> Note {
        var updated = note
        updated.syncState = state
        return updated
    }

    private func recordSyncState(noteID: UUID, contentHash: String, updatedAt: Date) async throws {
        try await syncStateRepository.setSyncState(NoteSyncState(
            noteID: noteID,
            lastSyncedContentHash: contentHash,
            lastSyncedUpdatedAt: updatedAt,
            lastSyncedAt: Date(),
            remoteDeviceID: deviceID
        ))
    }
}
