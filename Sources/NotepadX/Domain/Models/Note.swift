import Foundation

/// 노트가 어디서 만들어졌는지를 나타낸다.
enum NoteSource: String, Codable, Sendable, CaseIterable {
    case local
    case oneDrive
    case importedAppleNotes
}

/// OneDrive 등 외부 저장소와의 동기화 상태.
enum SyncState: String, Codable, Sendable, CaseIterable {
    case notSynced
    case syncing
    case synced
    case conflict
    case error
}

struct Note: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var folderID: UUID?
    var title: String
    /// EditorDocument를 JSON으로 인코딩한 값. Phase 1에서는 단일 문단으로 감싼 plainText를 저장한다.
    var documentJSON: Data
    /// 검색 인덱스와 목록 미리보기를 위해 documentJSON에서 파생한 순수 텍스트.
    var plainText: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var isFavorite: Bool
    var isPinned: Bool
    var source: NoteSource
    var contentHash: String
    var syncState: SyncState

    var isDeleted: Bool { deletedAt != nil }

    init(
        id: UUID = UUID(),
        folderID: UUID? = nil,
        title: String = "",
        documentJSON: Data,
        plainText: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        isFavorite: Bool = false,
        isPinned: Bool = false,
        source: NoteSource = .local,
        contentHash: String,
        syncState: SyncState = .notSynced
    ) {
        self.id = id
        self.folderID = folderID
        self.title = title
        self.documentJSON = documentJSON
        self.plainText = plainText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.source = source
        self.contentHash = contentHash
        self.syncState = syncState
    }
}

extension Note {
    /// 제목이 비어 있을 때 목록에 표시할 대체 문자열.
    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "제목 없음" : title
    }

    /// 노트 목록 미리보기용 한 줄 발췌.
    var previewText: String {
        let collapsed = plainText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= 120 { return collapsed }
        let idx = collapsed.index(collapsed.startIndex, offsetBy: 120)
        return String(collapsed[..<idx]) + "…"
    }
}
