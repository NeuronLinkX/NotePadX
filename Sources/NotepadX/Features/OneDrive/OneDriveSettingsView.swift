import SwiftUI

/// OneDrive 폴더 선택/해제, 지금 동기화, 충돌 해결까지 한 시트에서 처리한다 (스펙 13절).
struct OneDriveSettingsView: View {
    @ObservedObject var viewModel: OneDriveViewModel
    @ObservedObject private var folderAccessService: FolderAccessService
    @Environment(\.dismiss) private var dismiss

    init(viewModel: OneDriveViewModel) {
        self.viewModel = viewModel
        self._folderAccessService = ObservedObject(wrappedValue: viewModel.folderAccessService)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("OneDrive 동기화").font(.title2.bold())
                Spacer()
                Button("닫기") { dismiss() }
            }

            folderSection

            if folderAccessService.folderURL != nil {
                syncSection
            }

            if !viewModel.conflicts.isEmpty {
                conflictsSection
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 480, height: 420)
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("동기화 폴더").font(.headline)

            if folderAccessService.needsReselection {
                Label("이전에 선택한 폴더에 접근할 수 없습니다. 다시 선택해 주세요.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            if let url = folderAccessService.folderURL {
                Label(url.path, systemImage: "folder.fill")
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("아직 폴더를 선택하지 않았습니다. OneDrive 폴더(또는 그 하위 폴더)를 선택하면 그 안에 노트가 저장됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(folderAccessService.folderURL == nil ? "폴더 선택…" : "다른 폴더 선택…") {
                    viewModel.chooseFolder()
                }
                if folderAccessService.folderURL != nil {
                    Button("연결 해제", role: .destructive) {
                        viewModel.forgetFolder()
                    }
                }
            }
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("동기화").font(.headline)

            if let summary = viewModel.lastSyncSummary {
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                if viewModel.isSyncing {
                    ProgressView().controlSize(.small)
                    Text("동기화 중…")
                }
                Button("지금 동기화") {
                    Task { await viewModel.syncAll() }
                }
                .disabled(viewModel.isSyncing)
            }
        }
    }

    private var conflictsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("충돌 (\(viewModel.conflicts.count)개)").font(.headline)
            Text("같은 노트가 로컬과 OneDrive 양쪽에서 바뀌었습니다. 자동으로 덮어쓰지 않으니 직접 선택해 주세요.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(viewModel.conflicts) { conflict in
                VStack(alignment: .leading, spacing: 4) {
                    Text(conflict.localTitle.isEmpty ? "제목 없음" : conflict.localTitle).font(.subheadline.bold())
                    HStack {
                        Button("로컬 유지") { Task { await viewModel.resolve(conflict, as: .keepLocal) } }
                        Button("OneDrive 유지") { Task { await viewModel.resolve(conflict, as: .keepRemote) } }
                        Button("둘 다 보존") { Task { await viewModel.resolve(conflict, as: .keepBoth) } }
                    }
                    .font(.caption)
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 160)
        }
    }
}
