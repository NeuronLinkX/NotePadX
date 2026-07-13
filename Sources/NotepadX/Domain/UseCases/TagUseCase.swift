import Foundation

struct TagUseCase: Sendable {
    private let tagRepository: any TagRepository
    private let searchIndex: SearchIndexService

    init(tagRepository: any TagRepository, searchIndex: SearchIndexService) {
        self.tagRepository = tagRepository
        self.searchIndex = searchIndex
    }

    func fetchAllTags() async throws -> [Tag] {
        try await tagRepository.fetchAllTags()
    }

    func tags(forNote noteID: UUID) async throws -> [Tag] {
        try await tagRepository.tags(forNote: noteID)
    }

    @discardableResult
    func createTag(name: String) async throws -> Tag {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = Tag(name: trimmed.isEmpty ? "새 태그" : trimmed)
        try await tagRepository.createTag(tag)
        return tag
    }

    /// 이름이 같은 태그가 이미 있으면 그걸 재사용하고, 없으면 새로 만든다.
    func findOrCreateTag(name: String) async throws -> Tag {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = try await tagRepository.fetchAllTags().first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        return try await createTag(name: trimmed)
    }

    func rename(id: UUID, to newName: String) async throws {
        try await tagRepository.renameTag(id: id, newName: newName)
    }

    func setColor(id: UUID, colorHex: String?) async throws {
        try await tagRepository.setColor(id: id, colorHex: colorHex)
    }

    func delete(id: UUID) async throws {
        try await tagRepository.deleteTag(id: id)
    }

    func noteCount(tagID: UUID) async throws -> Int {
        try await tagRepository.noteCount(tagID: tagID)
    }

    /// 노트의 태그 집합을 통째로 교체하고 검색 색인을 갱신한다.
    func setTags(noteID: UUID, tagIDs: [UUID]) async throws {
        try await tagRepository.setTags(noteID: noteID, tagIDs: tagIDs)
        try await searchIndex.reindexNote(id: noteID)
    }
}
