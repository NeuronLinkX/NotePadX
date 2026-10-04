import SwiftUI
import WidgetKit

struct RecentNotesEntry: TimelineEntry {
    let date: Date
    /// nil이면 앱이 아직 한 번도 요약을 내보내지 않은 상태(앱을 처음 실행하기 전)다.
    let notes: [WidgetNoteSummary]?
}

struct RecentNotesProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentNotesEntry {
        RecentNotesEntry(date: Date(), notes: Self.sampleNotes)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentNotesEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : loadEntry())
    }

    // 앱이 비활성화될 때마다 reloadAllTimelines()로 즉시 갱신하고, 앱이 꺼져 있는 동안에는
    // 15분마다 파일을 다시 읽는다(OneDrive 동기화 등으로 바뀔 수 있으므로).
    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentNotesEntry>) -> Void) {
        completion(Timeline(entries: [loadEntry()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func loadEntry() -> RecentNotesEntry {
        RecentNotesEntry(date: Date(), notes: WidgetSnapshotStore.read()?.notes)
    }

    private static let sampleNotes: [WidgetNoteSummary] = [
        WidgetNoteSummary(id: UUID(), title: "학술대회 준비", preview: "9월 1일 염선호 박사님 Comment", updatedAt: Date(), isFavorite: true, isPinned: false),
        WidgetNoteSummary(id: UUID(), title: "해양 데이터", preview: "[목적] 해양안전심판원(KMST) 공개 재결서", updatedAt: Date().addingTimeInterval(-3600), isFavorite: false, isPinned: false),
        WidgetNoteSummary(id: UUID(), title: "RAG 메모", preview: "RAG를 사용하지 않은 근거 지식 유도", updatedAt: Date().addingTimeInterval(-7200), isFavorite: false, isPinned: false),
    ]
}

struct RecentNotesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecentNotesEntry

    private var visibleCount: Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 3
        default: 7
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(family == .systemSmall ? entry.notes?.first.map { WidgetDeepLink.url(forNote: $0.id) } : nil)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "note.text")
                .foregroundStyle(.tint)
            Text("최근 메모")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Spacer()
            if family != .systemSmall {
                Link(destination: WidgetDeepLink.newNoteURL) {
                    Image(systemName: "square.and.pencil")
                        .font(.caption.bold())
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let notes = entry.notes {
            if notes.isEmpty {
                Text("메모가 없습니다")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if family == .systemSmall, let note = notes.first {
                smallNote(note)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(notes.prefix(visibleCount)) { note in
                        Link(destination: WidgetDeepLink.url(forNote: note.id)) {
                            row(note)
                        }
                    }
                }
            }
        } else {
            Text("NotepadX를 한 번 실행하면 최근 메모가 여기에 표시됩니다")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func smallNote(_ note: WidgetNoteSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            titleLine(note)
                .font(.headline)
                .lineLimit(2)
            Text(note.preview.isEmpty ? "추가 텍스트 없음" : note.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
    }

    private func row(_ note: WidgetNoteSummary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                titleLine(note)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(note.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(note.preview.isEmpty ? "추가 텍스트 없음" : note.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(family == .systemLarge ? 2 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func titleLine(_ note: WidgetNoteSummary) -> Text {
        note.isFavorite
            ? Text("\(Image(systemName: "star.fill")) ").foregroundStyle(.yellow) + Text(note.title)
            : Text(note.title)
    }
}

struct RecentNotesWidget: Widget {
    let kind = "NotepadXRecentNotes"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecentNotesProvider()) { entry in
            RecentNotesWidgetView(entry: entry)
        }
        .configurationDisplayName("최근 메모")
        .description("가장 최근에 수정한 메모를 보고, 눌러서 바로 엽니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct NotepadXWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecentNotesWidget()
    }
}
