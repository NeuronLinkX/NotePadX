import SwiftUI

/// 설정 > 백업. 자동 백업, 외부 폴더 추가 보관, 수동 백업, 데이터 점검, 백업에서 복원.
struct BackupSettingsView: View {
    @StateObject private var viewModel = BackupSettingsViewModel()

    var body: some View {
        Form {
            if viewModel.hasStagedRestore {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("복원이 예약되어 있습니다").font(.headline)
                            Text("앱을 종료한 뒤 다시 켜면 적용됩니다. 그때까지 쓴 내용은 복원되며 사라지지만, 현재 상태는 '복원 전' 백업에 남아 있습니다.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("취소") { viewModel.cancelStagedRestore() }
                        Button("지금 종료") { viewModel.quitNow() }.buttonStyle(.borderedProminent)
                    }
                }
            }

            Section("자동 백업") {
                Toggle("하루 한 번 자동으로 백업", isOn: $viewModel.isAutoBackupEnabled)
                Stepper(value: $viewModel.keepCount, in: DatabaseBackupService.keepCountRange) {
                    Text("자동 백업 보관 개수: \(viewModel.keepCount)개")
                }
                LabeledContent("마지막 자동 백업", value: viewModel.lastAutoBackupText)
            }

            Section {
                if let path = viewModel.externalPath {
                    LabeledContent("추가 보관 폴더") {
                        Text(path).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("다른 폴더 선택…") { viewModel.chooseExternalFolder() }
                        Button("해제") { viewModel.clearExternalFolder() }
                    }
                } else {
                    Button("백업을 추가로 보관할 폴더 선택…") { viewModel.chooseExternalFolder() }
                }
                if let error = viewModel.externalError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("추가 보관 위치 (선택)")
            } footer: {
                Text("앱 안의 백업은 이 Mac에만 있습니다. OneDrive나 iCloud Drive 폴더를 고르면 Mac이 고장 나거나 앱이 삭제돼도 메모를 지킬 수 있습니다.")
            }

            Section("지금") {
                HStack {
                    Button {
                        viewModel.backupNow()
                    } label: {
                        Label("지금 백업", systemImage: "externaldrive.badge.plus")
                    }
                    .disabled(viewModel.isWorking || !viewModel.isReady)

                    Button {
                        viewModel.runIntegrityCheck()
                    } label: {
                        Label("데이터 점검", systemImage: "checkmark.shield")
                    }
                    .disabled(viewModel.isWorking || !viewModel.isReady)

                    if viewModel.isWorking { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("폴더 열기") { viewModel.revealBackupFolder() }
                }
                if let info = viewModel.infoMessage {
                    Label(info, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
                if let result = viewModel.checkResult {
                    Label(result, systemImage: result.hasPrefix("문제 없음") ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("문제 없음") ? Color.green : Color.orange)
                }
            }

            Section {
                if let stats = viewModel.storageStats {
                    LabeledContent("데이터베이스 전체", value: BackupSettingsViewModel.sizeText(stats.databaseBytes))
                    LabeledContent("메모 본문", value: BackupSettingsViewModel.sizeText(stats.noteBytes))
                    LabeledContent("버전 기록 \(stats.revisionCount)개", value: BackupSettingsViewModel.sizeText(stats.revisionBytes))
                    if stats.inlineImageRevisionCount > 0 {
                        Label("이미지가 통째로 중복 저장된 버전 기록이 \(stats.inlineImageRevisionCount)개 있습니다. 정리하면 같은 이미지를 한 번만 보관합니다.",
                              systemImage: "photo.on.rectangle.angled")
                            .font(.caption).foregroundStyle(.orange)
                    }
                } else {
                    Text("불러오는 중…").foregroundStyle(.secondary)
                }
                HStack {
                    Button {
                        viewModel.compactStorage()
                    } label: {
                        Label("저장 공간 정리", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    .disabled(viewModel.isCompacting || viewModel.isWorking || !viewModel.isReady || (viewModel.storageStats?.inlineImageRevisionCount ?? 0) == 0)
                    if viewModel.isCompacting { ProgressView().controlSize(.small) }
                }
                if let message = viewModel.compactionMessage {
                    Label(message, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
            } header: {
                Text("저장 공간")
            } footer: {
                Text("정리는 먼저 안전 백업을 만든 뒤, 각 버전 기록이 원본과 완전히 같게 복원되는지 확인한 것만 바꿉니다. 메모 내용은 달라지지 않습니다.")
            }

            Section("백업 목록 (\(viewModel.records.count))") {
                if viewModel.records.isEmpty {
                    Text("아직 백업이 없습니다. '지금 백업'을 눌러 첫 백업을 만들어 보세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(viewModel.records) { record in
                    row(record)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 760)
        .task { await viewModel.refreshReadiness() }
        .onAppear { viewModel.reload() }
        .confirmationDialog(
            "이 백업으로 복원할까요?",
            isPresented: Binding(get: { viewModel.restoreCandidate != nil }, set: { if !$0 { viewModel.restoreCandidate = nil } }),
            titleVisibility: .visible
        ) {
            Button("복원 준비", role: .destructive) { viewModel.performRestore() }
            Button("취소", role: .cancel) {}
        } message: {
            if let record = viewModel.restoreCandidate {
                Text("\(record.createdAt.formatted(date: .abbreviated, time: .shortened)) 시점으로 되돌립니다. 지금 데이터는 먼저 '복원 전' 백업으로 저장되고, 앱을 다시 켤 때 복원이 적용됩니다.")
            }
        }
        .alert("복원을 준비했습니다", isPresented: $viewModel.showQuitNotice) {
            Button("지금 종료") { viewModel.quitNow() }
            Button("나중에", role: .cancel) {}
        } message: {
            Text("앱을 종료한 뒤 다시 실행하면 복원이 적용됩니다. 지금 종료할까요?")
        }
        .alert("오류", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func row(_ record: BackupRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: record.isExternal ? "icloud" : "internaldrive")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text("\(record.kind.label) · \(BackupSettingsViewModel.sizeText(record.byteCount))\(record.isExternal ? " · 추가 보관 폴더" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("복원…") { viewModel.restoreCandidate = record }
                .disabled(viewModel.isWorking || !viewModel.isReady)
            Button(role: .destructive) { viewModel.delete(record) } label: { Image(systemName: "trash") }
                .help("이 백업 삭제")
                .accessibilityLabel("이 백업 삭제")
        }
        .buttonStyle(.borderless)
    }
}
