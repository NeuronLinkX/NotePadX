import Foundation

struct SearchHit: Identifiable, Sendable, Equatable {
    var noteID: UUID
    var title: String
    /// 검색어 주변을 잘라낸 미리보기 텍스트. 하이라이트 범위는 뷰가 원본 쿼리로 다시 찾는다.
    var snippet: String
    var updatedAt: Date

    var id: UUID { noteID }
}

struct SearchFilters: Sendable, Equatable {
    var folderID: UUID?
    var tagID: UUID?
    var favoritesOnly: Bool = false
    var createdAfter: Date?
    var createdBefore: Date?
    var updatedAfter: Date?
    var updatedBefore: Date?

    var isEmpty: Bool {
        folderID == nil && tagID == nil && !favoritesOnly
            && createdAfter == nil && createdBefore == nil
            && updatedAfter == nil && updatedBefore == nil
    }
}
