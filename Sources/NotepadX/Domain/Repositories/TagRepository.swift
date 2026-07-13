import Foundation

protocol TagRepository: Sendable {
    func fetchAllTags() async throws -> [Tag]
    func createTag(_ tag: Tag) async throws
    func renameTag(id: UUID, newName: String) async throws
    func setColor(id: UUID, colorHex: String?) async throws
    func deleteTag(id: UUID) async throws
    func noteCount(tagID: UUID) async throws -> Int

    func tags(forNote noteID: UUID) async throws -> [Tag]
    /// 현재 태그 집합을 통째로 이 목록으로 치환한다 (추가분 삽입 + 빠진 것 삭제).
    func setTags(noteID: UUID, tagIDs: [UUID]) async throws
}
