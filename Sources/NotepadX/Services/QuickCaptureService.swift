import Foundation

extension Notification.Name {
    /// 빠른 메모·단축어처럼 메인 창 밖에서 메모가 만들어졌을 때, 열려 있는 목록이 다시 불러오게 한다.
    static let notesChangedExternally = Notification.Name("NotepadX.notesChangedExternally")
}

/// 입력한 글을 메모로 저장한다. 첫 번째 비어 있지 않은 줄이 제목이 되고, 나머지가 본문이 된다
/// (제목 칸과 본문이 따로 있는 이 앱의 편집기와 같은 모양으로 맞춘다).
struct QuickCaptureService: Sendable {
    static let maxTitleLength = 80

    let noteUseCase: NoteUseCase

    /// 순수 함수라 따로 시험한다. 내용이 비어 있으면 nil.
    static func split(_ text: String) -> (title: String, body: String)? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard let firstIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
        let rawTitle = lines[firstIndex].trimmingCharacters(in: .whitespaces)
        let title = rawTitle.count > maxTitleLength ? String(rawTitle.prefix(maxTitleLength)) + "…" : rawTitle
        // 제목이 잘렸다면 잘린 부분도 본문에 남겨 내용이 사라지지 않게 한다.
        var bodyLines = Array(lines[(firstIndex + 1)...])
        if rawTitle.count > maxTitleLength { bodyLines.insert(rawTitle, at: 0) }
        while let last = bodyLines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { bodyLines.removeLast() }
        return (title, bodyLines.joined(separator: "\n"))
    }

    @discardableResult
    func save(text: String, folderID: UUID? = nil) async throws -> Note? {
        guard let parts = Self.split(text) else { return nil }
        var note = try await noteUseCase.createNote(folderID: folderID)
        note = try noteUseCase.applyEdit(
            to: note,
            title: parts.title,
            document: EditorDocument.fromPlainText(parts.body),
            plainText: parts.body
        )
        try await noteUseCase.save(note)
        NotificationCenter.default.post(name: .notesChangedExternally, object: nil, userInfo: ["id": note.id])
        return note
    }
}
