import SwiftUI

struct RevisionHistoryView: View {
    @ObservedObject var viewModel: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRevisionID: UUID?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private var selectedRevision: NoteRevision? {
        viewModel.revisions.first { $0.id == selectedRevisionID }
    }

    var body: some View {
        NavigationSplitView {
            List(viewModel.revisions, selection: $selectedRevisionID) { revision in
                VStack(alignment: .leading, spacing: 2) {
                    Text(reasonLabel(revision.reason)).font(.subheadline)
                    Text(Self.dateFormatter.string(from: revision.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(revision.id)
            }
            .navigationTitle("버전 기록")
            .overlay {
                if viewModel.revisions.isEmpty {
                    ContentUnavailableView("저장된 버전이 없습니다", systemImage: "clock.arrow.circlepath")
                }
            }
        } detail: {
            if let selectedRevision {
                RevisionDiffView(oldText: selectedRevision.plainText, newText: viewModel.note?.plainText ?? "")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("이 버전으로 복원") {
                                Task {
                                    await viewModel.restoreRevision(selectedRevision)
                                    dismiss()
                                }
                            }
                        }
                    }
            } else {
                ContentUnavailableView("왼쪽에서 버전을 선택하세요", systemImage: "doc.text.magnifyingglass")
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .task { await viewModel.loadRevisions() }
    }

    private func reasonLabel(_ reason: NoteRevisionReason) -> String {
        switch reason {
        case .periodicEdit: return "자동 저장 버전"
        case .manualSnapshot: return "수동 저장 버전"
        case .beforeLargeChange: return "큰 변경 전 버전"
        case .beforeRestore: return "복원 전 자동 보관"
        case .beforeLLMReplace: return "AI 적용 전 버전"
        case .beforeExternalSync: return "동기화 전 버전"
        case .beforeConflictResolution: return "충돌 해결 전 버전"
        }
    }
}

private struct RevisionDiffView: View {
    let oldText: String
    let newText: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(TextDiff.compute(old: oldText, new: newText)) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Text(line.kind.marker)
                            .frame(width: 14)
                        Text(line.text.isEmpty ? " " : line.text)
                        Spacer(minLength: 0)
                    }
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(line.kind.background)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

/// 이전 버전(old, 왼쪽 리스트에서 선택한 리비전)과 현재 노트(new)를 줄 단위로 비교한다.
enum TextDiff {
    struct Line: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind

        enum Kind: Equatable {
            case unchanged, added, removed

            var marker: String {
                switch self {
                case .unchanged: return " "
                case .added: return "+"
                case .removed: return "-"
                }
            }

            var background: Color {
                switch self {
                case .unchanged: return .clear
                case .added: return .green.opacity(0.15)
                case .removed: return .red.opacity(0.15)
                }
            }
        }
    }

    static func compute(old: String, new: String) -> [Line] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")
        let diff = newLines.difference(from: oldLines)

        var removedOffsets = Set<Int>()
        var insertedOffsets = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removedOffsets.insert(offset)
            case .insert(let offset, _, _): insertedOffsets.insert(offset)
            }
        }

        var result: [Line] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < oldLines.count || newIndex < newLines.count {
            if oldIndex < oldLines.count, removedOffsets.contains(oldIndex) {
                result.append(Line(text: oldLines[oldIndex], kind: .removed))
                oldIndex += 1
            } else if newIndex < newLines.count, insertedOffsets.contains(newIndex) {
                result.append(Line(text: newLines[newIndex], kind: .added))
                newIndex += 1
            } else if oldIndex < oldLines.count, newIndex < newLines.count {
                result.append(Line(text: newLines[newIndex], kind: .unchanged))
                oldIndex += 1
                newIndex += 1
            } else {
                break
            }
        }
        return result
    }
}
