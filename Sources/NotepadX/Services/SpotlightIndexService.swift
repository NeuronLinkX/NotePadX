import CoreSpotlight
import Foundation
import OSLog
import UniformTypeIdentifiers

/// 메모를 Spotlight(⌘Space)에서 찾아 열 수 있게 시스템 색인에 등록한다. 잠긴 메모와 휴지통의 메모는
/// 넣지 않고, 사용자가 끄면 등록한 항목을 전부 지운다.
actor SpotlightIndexService {
    static let shared = SpotlightIndexService()
    static let domain = "com.notepadx.note"
    static let enabledKey = "NotepadX.spotlight.enabled"
    static let previewsKey = "NotepadX.spotlight.previews"

    private static let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "spotlight")
    private var database: DatabaseManager?

    static var isEnabled: Bool { AppConfig.defaults.object(forKey: enabledKey) as? Bool ?? true }
    static var includesPreviews: Bool { AppConfig.defaults.object(forKey: previewsKey) as? Bool ?? true }

    func configure(database: DatabaseManager) {
        self.database = database
    }

    struct Row: Sendable, Equatable {
        let id: UUID
        let title: String
        let preview: String
        let updatedAt: Date
    }

    /// 격리 프로필(시연/시험)은 실사용 Spotlight를 건드리지 않는다. `NOTEPADX_SPOTLIGHT_FORCE=1`로만 예외.
    private static var isAllowedHere: Bool {
        !AppConfig.isIsolatedProfile || ProcessInfo.processInfo.environment["NOTEPADX_SPOTLIGHT_FORCE"] == "1"
    }

    func refresh() async {
        guard Self.isAllowedHere else { return }
        let index = CSSearchableIndex.default()
        guard Self.isEnabled else {
            try? await index.deleteSearchableItems(withDomainIdentifiers: [Self.domain])
            return
        }
        guard let database else { return }
        do {
            let rows = try await Self.rows(from: database)
            let items = Self.makeItems(rows: rows, includePreviews: Self.includesPreviews)
            // 지워진/잠긴 메모가 남지 않도록 통째로 비우고 다시 등록한다(수천 개까지는 부담 없는 규모).
            try await index.deleteSearchableItems(withDomainIdentifiers: [Self.domain])
            if !items.isEmpty { try await index.indexSearchableItems(items) }
            Self.logger.info("indexed \(items.count) notes")
        } catch {
            Self.logger.error("indexing failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func rows(from database: DatabaseManager) async throws -> [Row] {
        try await database.query(
            """
            SELECT id, title, substr(plain_text, 1, 200), updated_at FROM note \
            WHERE deleted_at IS NULL AND is_locked = 0 ORDER BY updated_at DESC LIMIT 5000;
            """
        ) { row -> Row? in
            guard let idString = row.string(0), let id = UUID(uuidString: idString) else { return nil }
            let title = (row.string(1) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Row(
                id: id,
                title: title.isEmpty ? "제목 없음" : title,
                preview: WidgetSnapshotService.preview(from: row.string(2) ?? ""),
                updatedAt: row.date(3) ?? Date()
            )
        }.compactMap { $0 }
    }

    static func makeItems(rows: [Row], includePreviews: Bool) -> [CSSearchableItem] {
        rows.map { row in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = row.title
            attributes.contentDescription = includePreviews ? row.preview : nil
            attributes.contentModificationDate = row.updatedAt
            attributes.keywords = ["Notepad", "NotepadX", "메모"]
            return CSSearchableItem(uniqueIdentifier: row.id.uuidString, domainIdentifier: domain, attributeSet: attributes)
        }
    }

    /// Spotlight 결과를 눌러 앱이 열릴 때 넘어오는 항목 id.
    static func noteID(from activity: NSUserActivity) -> UUID? {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        return UUID(uuidString: identifier)
    }
}

/// 앱 밖 표면(바탕화면 위젯, Spotlight)을 한꺼번에 최신으로 맞춘다. 앱을 떠날 때·종료할 때·시작할 때 부른다.
enum ExternalSurfaces {
    static func refresh() async {
        await WidgetSnapshotService.shared.refresh()
        await SpotlightIndexService.shared.refresh()
    }
}
