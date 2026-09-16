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
    /// 왼쪽 검색창에서 검색 중일 때의 검색어. nil/빈 문자열이 아니면 노트를 연 직후
    /// 본문에서도 같은 검색어로 하이라이트한다.
    var searchHighlightQuery: String? = nil
    /// nil이면 "연관 메모" 토글 버튼을 보여주지 않는다(분할의 보조 패널에서는 생략한다 —
    /// 이 그래프는 노트 하나가 아니라 창 전체에 딸린 부가 시각화라서 하나만 있으면 된다).
    var noteGraphViewModel: NoteGraphViewModel? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var isShowingRevisionHistory = false
    @State private var isShowingExport = false
    @StateObject private var llmPanelViewModel: LLMPanelViewModel

    init(
        viewModel: EditorViewModel,
        noteID: Binding<UUID?>,
        availableTags: [Tag],
        notePickerOptions: [Note]? = nil,
        onClosePane: (() -> Void)? = nil,
        searchHighlightQuery: String? = nil,
        noteGraphViewModel: NoteGraphViewModel? = nil
    ) {
        self.viewModel = viewModel
        self._noteID = noteID
        self.availableTags = availableTags
        self.notePickerOptions = notePickerOptions
        self.onClosePane = onClosePane
        self.searchHighlightQuery = searchHighlightQuery
        self.noteGraphViewModel = noteGraphViewModel
        _llmPanelViewModel = StateObject(wrappedValue: LLMPanelViewModel(editorViewModel: viewModel))
    }

    var body: some View {
        let withSheets = mainStack
            .sheet(isPresented: $isShowingRevisionHistory) {
                RevisionHistoryView(viewModel: viewModel)
            }
            .sheet(isPresented: $isShowingExport) {
                exportSheetContent
            }
            .sheet(isPresented: $viewModel.isShowingGoToLine) {
                goToLineSheet
            }
            .sheet(isPresented: Binding(
                get: { viewModel.pdfPreviewURL != nil },
                set: { if !$0 { viewModel.pdfPreviewURL = nil } }
            )) {
                if let url = viewModel.pdfPreviewURL {
                    PDFPreviewSheet(url: url, onClose: { viewModel.pdfPreviewURL = nil })
                }
            }
        let withFocusedActions = withSheets
            .focusedSceneValue(\.exportAction, (viewModel.note != nil && !isDiagramNote) ? { isShowingExport = true } : nil)
            .focusedSceneValue(\.findAction, (viewModel.note != nil && !isDiagramNote) ? { viewModel.toggleFind() } : nil)
            .focusedSceneValue(\.replaceAction, (viewModel.note != nil && !isDiagramNote) ? { viewModel.toggleReplace() } : nil)
            .focusedSceneValue(\.goToLineAction, (viewModel.note != nil && !isDiagramNote) ? { viewModel.toggleGoToLine() } : nil)
        return withFocusedActions
            .task(id: noteID) {
                await viewModel.load(noteID: noteID)
                if let searchHighlightQuery, !searchHighlightQuery.isEmpty {
                    viewModel.highlightSearchMatches(searchHighlightQuery)
                }
            }
            .onChange(of: searchHighlightQuery) { _, newValue in
                if let newValue, !newValue.isEmpty {
                    viewModel.highlightSearchMatches(newValue)
                }
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

    @ViewBuilder
    private var exportSheetContent: some View {
        if let note = viewModel.note, let document = viewModel.exportDocument {
            ExportView(viewModel: ExportViewModel(), note: note, title: viewModel.title, document: document)
        }
    }

    private var mainStack: some View {
        HStack(spacing: 0) {
            if viewModel.isShowingOutline, viewModel.note != nil {
                DocumentOutlineView(viewModel: viewModel)
                Divider()
            }

            Group {
                if let note = viewModel.note, note.kind == .diagram {
                    VStack(spacing: 0) {
                        paneHeader
                        Divider()

                        TextField("제목", text: $viewModel.title)
                            .textFieldStyle(.plain)
                            .font(.title2.bold())
                            .padding([.horizontal, .top], 16)
                            .padding(.bottom, 4)
                            .onChange(of: viewModel.title) { _, _ in viewModel.titleChanged() }

                        TagChipsView(viewModel: viewModel, availableTags: availableTags)
                        Divider()

                        if let diagramDocument = viewModel.diagramDocument {
                            DiagramEditorView(document: Binding(
                                get: { diagramDocument },
                                set: { viewModel.updateDiagram($0) }
                            ))
                        } else {
                            ContentUnavailableView("다이어그램을 불러오는 중", systemImage: "square.on.square")
                        }
                    }
                } else if viewModel.note != nil {
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

            if let noteGraphViewModel, noteGraphViewModel.isVisible {
                Divider()
                NoteGraphPanelView(viewModel: noteGraphViewModel)
            }
        }
    }

    private var isDiagramNote: Bool { viewModel.note?.kind == .diagram }

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

            if !isDiagramNote {
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
            }

            if viewModel.note != nil {
                if !isDiagramNote {
                    Button { viewModel.isShowingOutline.toggle() } label: {
                        Image(systemName: "list.bullet.indent")
                    }
                    .foregroundStyle(viewModel.isShowingOutline ? Color.accentColor : Color.primary)
                    .help("문서 개요")
                    .accessibilityLabel("문서 개요")
                    .accessibilityAddTraits(viewModel.isShowingOutline ? [.isSelected] : [])
                }

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

                if !isDiagramNote {
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

                if let noteGraphViewModel {
                    Button { noteGraphViewModel.toggle() } label: {
                        Image(systemName: noteGraphViewModel.isVisible ? "point.3.connected.trianglepath.dotted" : "point.3.filled.connected.trianglepath.dotted")
                    }
                    .foregroundStyle(noteGraphViewModel.isVisible ? Color.accentColor : Color.primary)
                    .help("연관 메모")
                    .accessibilityLabel("연관 메모")
                    .accessibilityAddTraits(noteGraphViewModel.isVisible ? [.isSelected] : [])
                }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("찾기", text: $viewModel.findQuery, onCommit: { viewModel.performFind() })
                    .textFieldStyle(.plain)
                Button { viewModel.findCaseSensitive.toggle() } label: { Text("Aa").font(.caption.bold()) }
                    .foregroundStyle(viewModel.findCaseSensitive ? Color.accentColor : Color.secondary)
                    .help("대소문자 구분")
                    .accessibilityLabel("대소문자 구분")
                    .accessibilityAddTraits(viewModel.findCaseSensitive ? [.isSelected] : [])
                Button { viewModel.performFind(backwards: true) } label: { Image(systemName: "chevron.up") }
                    .help("이전 항목 찾기")
                    .accessibilityLabel("이전 항목 찾기")
                Button { viewModel.performFind() } label: { Image(systemName: "chevron.down") }
                    .help("다음 항목 찾기")
                    .accessibilityLabel("다음 항목 찾기")
                Button { viewModel.toggleReplace() } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                    .foregroundStyle(viewModel.isShowingReplace ? Color.accentColor : Color.secondary)
                    .help("바꾸기")
                    .accessibilityLabel("바꾸기")
                    .accessibilityAddTraits(viewModel.isShowingReplace ? [.isSelected] : [])
                if viewModel.findHasNoMatch, !viewModel.findQuery.isEmpty {
                    Text("일치하는 항목 없음").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { viewModel.toggleFind() } label: { Image(systemName: "xmark") }
                    .help("찾기 닫기")
                    .accessibilityLabel("찾기 닫기")
            }

            if viewModel.isShowingReplace {
                HStack {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                    TextField("바꿀 내용", text: $viewModel.replaceText, onCommit: { viewModel.replaceCurrentMatch() })
                        .textFieldStyle(.plain)
                    Button("바꾸기") { viewModel.replaceCurrentMatch() }
                        .disabled(viewModel.findQuery.isEmpty)
                    Button("모두 바꾸기") { viewModel.replaceAllMatches() }
                        .disabled(viewModel.findQuery.isEmpty)
                    if let message = viewModel.findStatusMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial)
    }

    private var goToLineSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("줄 번호로 이동").font(.headline)
            TextField("줄 번호", text: $viewModel.goToLineInput, onCommit: { viewModel.goToLine() })
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
            HStack {
                Spacer()
                Button("취소") { viewModel.toggleGoToLine() }
                Button("이동") { viewModel.goToLine() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(Int(viewModel.goToLineInput.trimmingCharacters(in: .whitespaces)) == nil)
            }
        }
        .padding(20)
        .frame(width: 260)
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
            Text("줄 \(viewModel.selection.line), 열 \(viewModel.selection.column)")
            Text(wordCountText)
            Text(viewModel.lineEndingStyle)
            Text(viewModel.textEncodingName)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    /// 윈도우 메모장처럼 선택 영역이 있으면 그 부분만, 없으면 문서 전체 글자수·단어수를 보여준다.
    private var wordCountText: String {
        if !viewModel.selection.empty, !viewModel.selection.selectedText.isEmpty {
            let text = viewModel.selection.selectedText
            return "선택 영역 \(text.count)자 · \(EditorViewModel.wordCount(in: text))단어"
        }
        return "\(viewModel.documentCharacterCount)자 · \(viewModel.documentWordCount)단어"
    }
}
