import SwiftUI

/// WKWebView 기반 리치 편집기(Tiptap) 패널 하나. 분할 편집(스펙 9절)에서 이 뷰가
/// 두 번 인스턴스화될 수 있으므로, 윈도우 전역 `.toolbar`가 아니라 패널 안쪽에
/// 자체 헤더(줌/찾기/버전 기록, 분할 중이면 노트 선택 + 닫기)를 둔다.
struct EditorView: View {
    @ObservedObject var viewModel: EditorViewModel
    @Binding var noteID: UUID?
    let availableTags: [Tag]

    /// nil이면 노트 선택 메뉴를 보여주지 않는다 (분할이 없을 때의 기본 패널).
    var notePickerOptions: [Note]? = nil
    /// nil이면 "분할 닫기" 버튼을 보여주지 않는다.
    var onClosePane: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var isShowingRevisionHistory = false
    @State private var isShowingExport = false
    @StateObject private var llmPanelViewModel: LLMPanelViewModel

    init(
        viewModel: EditorViewModel,
        noteID: Binding<UUID?>,
        availableTags: [Tag],
        notePickerOptions: [Note]? = nil,
        onClosePane: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self._noteID = noteID
        self.availableTags = availableTags
        self.notePickerOptions = notePickerOptions
        self.onClosePane = onClosePane
        _llmPanelViewModel = StateObject(wrappedValue: LLMPanelViewModel(editorViewModel: viewModel))
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if viewModel.note != nil {
                    VStack(spacing: 0) {
                        paneHeader
                        Divider()

                        if viewModel.externalConflict {
                            conflictBanner
                        }

                        if viewModel.isShowingFind {
                            findBar
                        }

                        TextField("제목", text: $viewModel.title)
                            .textFieldStyle(.plain)
                            .font(.title2.bold())
                            .padding([.horizontal, .top], 16)
                            .padding(.bottom, 4)
                            .onChange(of: viewModel.title) { _, _ in viewModel.titleChanged() }
                            .disabled(viewModel.displayMode == .preview)

                        TagChipsView(viewModel: viewModel, availableTags: availableTags)

                        Divider()
                        if viewModel.displayMode == .edit {
                            EditorToolbar(viewModel: viewModel)
                            Divider()
                        }

                        RichEditorWebView(controller: viewModel.richEditor)

                        Divider()
                        statusBar
                    }
                } else {
                    VStack(spacing: 0) {
                        paneHeader
                        Divider()
                        ContentUnavailableView("메모를 선택하세요", systemImage: "note.text")
                    }
                }
            }
            .frame(maxWidth: .infinity)

            if llmPanelViewModel.isVisible {
                Divider()
                LLMPanelView(viewModel: llmPanelViewModel)
            }
        }
        .sheet(isPresented: $isShowingRevisionHistory) {
            RevisionHistoryView(viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingExport) {
            if let note = viewModel.note, let document = viewModel.exportDocument {
                ExportView(viewModel: ExportViewModel(), note: note, title: viewModel.title, document: document)
            }
        }
        .focusedSceneValue(\.exportAction, viewModel.note != nil ? { isShowingExport = true } : nil)
        .task(id: noteID) {
            await viewModel.load(noteID: noteID)
        }
        .onAppear { viewModel.applyTheme(isDark: colorScheme == .dark) }
        .onChange(of: colorScheme) { _, newValue in viewModel.applyTheme(isDark: newValue == .dark) }
        .alert("오류", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var paneHeader: some View {
        HStack(spacing: 10) {
            if let notePickerOptions {
                Menu {
                    ForEach(notePickerOptions) { note in
                        Button(note.displayTitle) { noteID = note.id }
                    }
                } label: {
                    Text(viewModel.note?.displayTitle ?? "노트 선택")
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 160)
            }

            Spacer(minLength: 4)

            Button { viewModel.decreaseZoom() } label: { Image(systemName: "minus.magnifyingglass") }
                .help("축소")
                .accessibilityLabel("축소")
            Text("\(Int(viewModel.zoomLevel * 100))%").font(.caption).monospacedDigit().frame(width: 40)
                .accessibilityLabel("확대 비율 \(Int(viewModel.zoomLevel * 100))퍼센트")
            Button { viewModel.increaseZoom() } label: { Image(systemName: "plus.magnifyingglass") }
                .help("확대")
                .accessibilityLabel("확대")

            Button { viewModel.toggleFind() } label: { Image(systemName: "magnifyingglass") }
                .help("이 패널에서 찾기")
                .accessibilityLabel("이 패널에서 찾기")

            Picker("", selection: Binding(
                get: { viewModel.displayMode },
                set: { viewModel.setDisplayMode($0) }
            )) {
                Text("편집").tag(PaneDisplayMode.edit)
                Text("미리보기").tag(PaneDisplayMode.preview)
            }
            .pickerStyle(.segmented)
            .frame(width: 130)
            .disabled(viewModel.note == nil)

            if viewModel.note != nil {
                Menu {
                    Button("버전으로 저장") { Task { await viewModel.saveVersionSnapshot() } }
                    Button("버전 기록 보기…") { isShowingRevisionHistory = true }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("버전 기록")
                .accessibilityLabel("버전 기록")

                Button { isShowingExport = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("내보내기…")
                .accessibilityLabel("내보내기")

                Button { llmPanelViewModel.isVisible.toggle() } label: {
                    Image(systemName: llmPanelViewModel.isVisible ? "sparkles.rectangle.stack.fill" : "sparkles")
                }
                .help("AI 패널")
                .accessibilityLabel("AI 패널")
                .accessibilityAddTraits(llmPanelViewModel.isVisible ? [.isSelected] : [])
            }

            if let onClosePane {
                Button(action: onClosePane) {
                    Image(systemName: "xmark.circle")
                }
                .help("분할 닫기")
                .accessibilityLabel("분할 닫기")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var findBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("찾기", text: $viewModel.findQuery, onCommit: { viewModel.performFind() })
                .textFieldStyle(.plain)
            Button { viewModel.performFind(backwards: true) } label: { Image(systemName: "chevron.up") }
                .help("이전 항목 찾기")
                .accessibilityLabel("이전 항목 찾기")
            Button { viewModel.performFind() } label: { Image(systemName: "chevron.down") }
                .help("다음 항목 찾기")
                .accessibilityLabel("다음 항목 찾기")
            if viewModel.findHasNoMatch, !viewModel.findQuery.isEmpty {
                Text("일치하는 항목 없음").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { viewModel.toggleFind() } label: { Image(systemName: "xmark") }
                .help("찾기 닫기")
                .accessibilityLabel("찾기 닫기")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial)
    }

    private var conflictBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("다른 패널에서 이 노트를 먼저 저장했습니다. 지금 이 패널 내용을 이어서 저장하면 충돌할 수 있습니다.")
                .font(.caption)
            Spacer()
            Button("새로고침") { Task { await viewModel.reloadFromDisk() } }
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.15))
    }

    private var statusBar: some View {
        HStack {
            if viewModel.isSaving {
                ProgressView().controlSize(.small)
                Text("저장 중…")
            } else if viewModel.hasUnsavedChanges {
                Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.orange)
                Text("저장되지 않은 변경 사항")
            } else {
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                Text("저장됨")
            }
            Spacer()
            if let language = viewModel.selection.codeBlockLanguage {
                Text("코드 블록 · \(language)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
