import Foundation
import OSLog
import WidgetKit

/// 최근 메모 요약을 위젯이 읽는 JSON으로 내보내고, 위젯 타임라인을 다시 불러오게 한다.
actor WidgetSnapshotService {
    static let shared = WidgetSnapshotService()

    private var database: DatabaseManager?

    /// 위젯(large)이 보여줄 수 있는 최대 개수보다 넉넉하게 담는다.
    static let maxNotes = 12

    func configure(database: DatabaseManager) {
        self.database = database
    }

    private static let logger = Logger(subsystem: AppConfig.bundleIdentifier, category: "widget")

    /// 실패해도 앱 동작에는 영향이 없어야 하므로 사용자에게는 알리지 않는다 — 위젯은 보조
    /// 기능이다. 대신 원인을 로그(`log show --predicate 'category == "widget"'`)에 남긴다.
    func refresh() async {
        guard let database else {
            Self.logger.error("refresh skipped: database not configured")
            return
        }
        do {
            let snapshot = try await Self.makeSnapshot(from: database)
            try WidgetSnapshotStore.write(snapshot)
            Self.logger.info("wrote \(snapshot.notes.count) notes to \(WidgetSnapshotStore.defaultDirectoryURL().path, privacy: .public)")
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            Self.logger.error("refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func makeSnapshot(from database: DatabaseManager, limit: Int = maxNotes) async throws -> WidgetSnapshot {
        // updated_at 인덱스를 타도록 정렬은 DB에서 최신순만 하고, 고정(pin) 우선 정렬은
        // 후보 몇십 개에 대해 Swift에서 한다 — 노트 전체를 훑지 않는다.
        let sql = """
            SELECT id, title, substr(plain_text, 1, 240), updated_at, is_favorite, is_pinned \
            FROM note WHERE deleted_at IS NULL ORDER BY updated_at DESC LIMIT ?;
            """
        let candidates: [WidgetNoteSummary] = try await database.query(sql, [.int(Int64(limit * 4))]) { row in
            guard let idString = row.string(0), let id = UUID(uuidString: idString) else {
                throw AppError.documentCorrupted
            }
            let body = row.string(2) ?? ""
            let trimmedTitle = (row.string(1) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return WidgetNoteSummary(
                id: id,
                title: trimmedTitle.isEmpty ? "제목 없음" : trimmedTitle,
                preview: Self.preview(from: body),
                updatedAt: row.date(3) ?? Date(),
                isFavorite: row.bool(4) ?? false,
                isPinned: row.bool(5) ?? false
            )
        }
        let ordered = candidates.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isPinned != rhs.element.isPinned { return lhs.element.isPinned }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        return WidgetSnapshot(generatedAt: Date(), notes: Array(ordered.prefix(limit)))
    }

    static func preview(from plainText: String) -> String {
        let collapsed = plainText
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= 120 { return collapsed }
        return String(collapsed.prefix(120)) + "…"
    }
}
