import AppKit
import Foundation

@MainActor
final class EditorViewModel: NSObject, ObservableObject {
    @Published var title: String = ""
    @Published var isSaving = false
    @Published var hasUnsavedChanges = false
    @Published var errorMessage: String?
    @Published private(set) var selection = EditorSelectionState(
        from: 0, to: 0, empty: true, selectedText: "", activeMarks: [], activeBlockType: "paragraph",
        headingLevel: nil, codeBlockLanguage: nil, linkHref: nil, textColor: nil, fontSize: nil, fontFamily: nil
    )
    @Published private(set) var noteTags: [Tag] = []
    @Published private(set) var revisions: [NoteRevision] = []

    /// 저장이 성공할 때마다 호출한다 — 노트 목록(NoteListViewModel)이 제목/수정 시각을
    /// 즉시 반영하도록 ContentView에서 연결한다. 편집기와 목록이 서로 다른 뷰모델이라
    /// 이 콜백 없이는 저장해도 목록의 제목이 다음 전체 재조회 전까지 바뀌지 않는다.
    var onNoteUpdated: ((Note) -> Void)?

    /// 이 노트의 태그 집합이 바뀌어 저장에 성공할 때마다 호출한다 — 사이드바(SidebarViewModel)의
    /// "태그" 목록이 새 태그를 즉시 보여주도록 ContentView가 연결한다. 이 콜백이 없으면 편집기
    /// 안에서 새 태그를 만들어도 사이드바에는 앱을 다시 켤 때까지 나타나지 않는다.
    var onTagsChanged: (() -> Void)?

    /// 다른 패널이 같은 노트를 먼저 저장해서 이 패널의 자동저장이 조용히 덮어쓰는 대신 막힌 상태.
    @Published private(set) var externalConflict = false

    @Published var displayMode: PaneDisplayMode = .edit
    @Published var zoomLevel: Double = 1.0
    @Published var isShowingFind = false
    @Published var findQuery = ""
    @Published var findHasNoMatch = false
    @Published var isShowingOutline = false
    @Published private(set) var headingOutline: [HeadingOutlineItem] = []

    let richEditor = RichEditorController()

    /// SaveCoordinator 등록 키. note.id를 쓰면 같은 노트를 두 분할 패널에서 열었을 때
    /// 한쪽 등록이 다른 쪽을 덮어써서 종료 시 한쪽 자동저장이 유실된다 — 그래서 패널
    /// 인스턴스마다 고유한 값을 쓴다.
    private let paneInstanceID = UUID()

    private(set) var note: Note?
    /// 내보내기(Export) 시트가 지금 편집 중인 문서 구조를 읽을 수 있도록 노출한다.
    var exportDocument: EditorDocument? { lastDocument }
    private var isEditorReady = false
    private var lastDocument: EditorDocument?
    private var lastPlainText: String = ""
    private var pendingLoad: Note?
    private var lastRevisionSnapshotAt: Date?
    /// 이 패널이 마지막으로 확인한 "DB상 현재 상태"의 updated_at. CAS 저장의 기준값.
    private var baseUpdatedAt: Date = Date()

    private let noteUseCase: NoteUseCase
    private let tagUseCase: TagUseCase
    private let revisionUseCase: NoteRevisionUseCase
    private let attachmentStorage = AttachmentStorage()
    private var autosave: AutosaveService?

    init(noteUseCase: NoteUseCase, tagUseCase: TagUseCase, revisionUseCase: NoteRevisionUseCase) {
        self.noteUseCase = noteUseCase
        self.tagUseCase = tagUseCase
        self.revisionUseCase = revisionUseCase
        super.init()
        richEditor.delegate = self
        autosave = AutosaveService { [weak self] note in
            await self?.persist(note)
        }
    }

    func load(noteID: UUID?) async {
        if note != nil {
            await flush()
            SaveCoordinator.shared.unregister(id: paneInstanceID)
        }

        lastRevisionSnapshotAt = nil
        noteTags = []
        revisions = []
        externalConflict = false
        isShowingFind = false
        findQuery = ""
        headingOutline = []

        guard let noteID else {
            note = nil
            title = ""
            lastDocument = nil
            lastPlainText = ""
            hasUnsavedChanges = false
            headingOutline = []
            if isEditorReady { richEditor.loadDocument(.fromPlainText("")) }
            return
        }

        do {
            guard let loaded = try await noteUseCase.fetchNote(id: noteID) else {
                note = nil
                return
            }
            note = loaded
            title = loaded.title
            hasUnsavedChanges = false
            baseUpdatedAt = loaded.updatedAt
            let document = (try? EditorDocument.decode(from: loaded.documentJSON)) ?? .fromPlainText(loaded.plainText)
            lastDocument = document
            lastPlainText = loaded.plainText
            lastRevisionSnapshotAt = Date()

            if isEditorReady {
                richEditor.loadDocument(document)
            } else {
                pendingLoad = loaded
            }
            SaveCoordinator.shared.register(id: paneInstanceID) { [weak self] in
                await self?.flush()
            }

            noteTags = try await tagUseCase.tags(forNote: noteID)
        } catch {
            report(error)
        }
    }

    /// 다른 패널이 먼저 저장해 충돌이 난 뒤 사용자가 "새로고침"을 눌렀을 때.
    /// 이 패널의 저장되지 않은 변경 내용은 버려지고 DB의 최신 상태를 다시 불러온다.
    func reloadFromDisk() async {
        guard let noteID = note?.id else { return }
        await load(noteID: noteID)
    }

    /// 제목 TextField의 onChange에서 호출한다. 본문은 리치 에디터가 docChanged로 직접 보고한다.
    func titleChanged() {
        guard let current = note, let document = lastDocument else { return }
        applyAndScheduleSave(base: current, title: title, document: document, plainText: lastPlainText)
    }

    func flush() async {
        guard let note, hasUnsavedChanges else { return }
        await persist(note)
    }

    // MARK: - 포맷 툴바에서 호출하는 커맨드 전달

    func perform(command: String, args: [String: Any]? = nil) {
        richEditor.applyCommand(command, args: args)
    }

    /// 왼쪽 개요 패널에서 제목을 클릭했을 때. `pos`는 JS/ProseMirror가 매긴 위치를 그대로
    /// 왕복시키는 값이라 Swift에서는 해석하지 않는다.
    func scrollToHeading(_ item: HeadingOutlineItem) {
        richEditor.applyCommand("scrollToHeading", args: ["pos": item.pos])
    }

    // MARK: - 상태 표시줄 글자수·단어수 (윈도우 메모장 스타일 편의 기능)

    var documentCharacterCount: Int { lastPlainText.count }
    var documentWordCount: Int { Self.wordCount(in: lastPlainText) }

    static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    func applyTheme(isDark: Bool) {
        if isEditorReady { richEditor.setTheme(isDark: isDark) }
    }

    // MARK: - 패널 상태: 미리보기 / 확대 / 찾기 (스펙 9절 "각 편집기는 독립적인 상태를 가진다")

    func setDisplayMode(_ mode: PaneDisplayMode) {
        displayMode = mode
        if isEditorReady { richEditor.setEditable(mode == .edit) }
    }

    func increaseZoom() {
        zoomLevel = min(zoomLevel + 0.1, 2.0)
        richEditor.setZoom(zoomLevel)
    }

    func decreaseZoom() {
        zoomLevel = max(zoomLevel - 0.1, 0.5)
        richEditor.setZoom(zoomLevel)
    }

    func resetZoom() {
        zoomLevel = 1.0
        richEditor.setZoom(zoomLevel)
    }

    func toggleFind() {
        isShowingFind.toggle()
        if !isShowingFind { findQuery = "" }
    }

    func performFind(backwards: Bool = false) {
        guard !findQuery.isEmpty else { return }
        richEditor.find(findQuery, backwards: backwards) { [weak self] found in
            self?.findHasNoMatch = !found
        }
    }

    // MARK: - 태그

    func addTag(_ tag: Tag) async {
        guard let note, !noteTags.contains(where: { $0.id == tag.id }) else { return }
        noteTags.append(tag)
        await persistTags(noteID: note.id)
    }

    func createAndAddTag(name: String) async {
        guard let note else { return }
        do {
            let tag = try await tagUseCase.findOrCreateTag(name: name)
            guard !noteTags.contains(where: { $0.id == tag.id }) else { return }
            noteTags.append(tag)
            await persistTags(noteID: note.id)
        } catch {
            report(error)
        }
    }

    func removeTag(_ tag: Tag) async {
        guard let note else { return }
        noteTags.removeAll { $0.id == tag.id }
        await persistTags(noteID: note.id)
    }

    private func persistTags(noteID: UUID) async {
        do {
            try await tagUseCase.setTags(noteID: noteID, tagIDs: noteTags.map(\.id))
            onTagsChanged?()
        } catch {
            report(error)
        }
    }

    // MARK: - 버전 기록

    func loadRevisions() async {
        guard let note else { return }
        do {
            revisions = try await revisionUseCase.revisions(forNote: note.id)
        } catch {
            report(error)
        }
    }

    /// 사용자가 명시적으로 "버전으로 저장"을 눌렀을 때.
    func saveVersionSnapshot() async {
        guard let note else { return }
        await flush()
        do {
            try await revisionUseCase.snapshot(note: note, reason: .manualSnapshot)
            lastRevisionSnapshotAt = Date()
            await loadRevisions()
        } catch {
            report(error)
        }
    }

    /// 복원 전 현재 버전을 자동 보관한 뒤 되돌린다.
    func restoreRevision(_ revision: NoteRevision) async {
        do {
            let restored = try await revisionUseCase.restore(revisionID: revision.id)
            note = restored
            title = restored.title
            baseUpdatedAt = restored.updatedAt
            let document = (try? EditorDocument.decode(from: restored.documentJSON)) ?? .fromPlainText(restored.plainText)
            lastDocument = document
            lastPlainText = restored.plainText
            hasUnsavedChanges = false
            externalConflict = false
            if isEditorReady { richEditor.loadDocument(document) }
            onNoteUpdated?(restored)
            await loadRevisions()
        } catch {
            report(error)
        }
    }

    // MARK: - LLM 패널 연동 (스펙 16/17절)

    /// LLM 응답으로 문서를 크게 바꾸기 직전에 호출한다 — 복원 가능하도록 리비전을 남긴다.
    func snapshotBeforeLLMReplace() async {
        guard let note else { return }
        await flush()
        do {
            try await revisionUseCase.snapshot(note: note, reason: .beforeLLMReplace)
            await loadRevisions()
        } catch {
            report(error)
        }
    }

    /// LLM 응답을 "새 메모로 생성"할 때 쓴다. 지금 열려 있는 노트와 같은 폴더에 만든다.
    func createNoteFromText(title: String, text: String) async {
        do {
            let created = try await noteUseCase.createNote(folderID: note?.folderID)
            let document = EditorDocument.fromPlainText(text)
            let updated = try noteUseCase.applyEdit(to: created, title: title, document: document, plainText: text)
            try await noteUseCase.save(updated)
        } catch {
            report(error)
        }
    }

    // MARK: - 내부

    private func applyAndScheduleSave(base: Note, title: String, document: EditorDocument, plainText: String) {
        do {
            let updated = try noteUseCase.applyEdit(to: base, title: title, document: document, plainText: plainText)
            note = updated
            hasUnsavedChanges = true
            autosave?.scheduleSave(updated)
        } catch {
            report(error)
        }
    }

    private func persist(_ note: Note) async {
        isSaving = true
        do {
            let didSave = try await noteUseCase.saveIfUnchanged(note, expectedUpdatedAt: baseUpdatedAt)
            if didSave {
                hasUnsavedChanges = false
                baseUpdatedAt = note.updatedAt
                externalConflict = false
                onNoteUpdated?(note)
                await snapshotIfPeriodicIntervalElapsed(note)
            } else {
                // 다른 패널(또는 다른 창)이 먼저 저장했다. 자동으로 덮어쓰거나 재시도하지 않고
                // 사용자가 명시적으로 새로고침하거나 계속 편집해서 다음 자동저장을 기다리게 한다.
                externalConflict = true
            }
        } catch {
            report(error)
        }
        isSaving = false
    }

    /// 스펙 11절 "일정 시간 이상 편집 후" 조건. 저장이 성공한 시점 기준으로 판단한다.
    private func snapshotIfPeriodicIntervalElapsed(_ note: Note) async {
        let elapsed = lastRevisionSnapshotAt.map { Date().timeIntervalSince($0) } ?? .infinity
        guard elapsed >= NoteRevisionUseCase.periodicSnapshotInterval else { return }
        do {
            try await revisionUseCase.snapshot(note: note, reason: .periodicEdit)
            lastRevisionSnapshotAt = Date()
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        errorMessage = (error as? AppError)?.errorDescription ?? error.localizedDescription
    }
}

extension EditorViewModel: EditorBridgeDelegate {
    func editorBridgeDidBecomeReady(_ bridge: EditorBridge) {
        isEditorReady = true
        richEditor.setZoom(zoomLevel)
        richEditor.setEditable(displayMode == .edit)
        if let pending = pendingLoad {
            let document = (try? EditorDocument.decode(from: pending.documentJSON)) ?? .fromPlainText(pending.plainText)
            richEditor.loadDocument(document)
            pendingLoad = nil
        }
    }

    func editorBridge(_ bridge: EditorBridge, didChangeDocument document: EditorDocument, plainText: String) {
        guard let current = note else { return }
        lastDocument = document
        lastPlainText = plainText
        applyAndScheduleSave(base: current, title: title, document: document, plainText: plainText)
    }

    func editorBridge(_ bridge: EditorBridge, didChangeHeadings headings: [HeadingOutlineItem]) {
        headingOutline = headings
    }

    func editorBridge(_ bridge: EditorBridge, didChangeSelection selectionState: EditorSelectionState) {
        selection = selectionState
    }

    func editorBridge(_ bridge: EditorBridge, didRequestOpenExternalLink url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// 이미지가 아닌 파일을 드래그·붙여넣기했을 때. 문서에는 이미 JS가 fileAttachment
    /// 노드를 넣어 뒀으므로(같은 attachmentId로), 여기서는 실제 바이트를 디스크에 쓰기만
    /// 하면 된다 — 실패해도 노트 저장 자체를 막지 않고 오류만 알린다.
    func editorBridge(_ bridge: EditorBridge, didRequestSaveAttachment payload: SaveAttachmentPayload) {
        do {
            try attachmentStorage.save(attachmentId: payload.attachmentId, fileName: payload.fileName, base64Data: payload.base64Data)
        } catch {
            report(error)
        }
    }

    /// 첨부파일 카드를 클릭했을 때 기본 앱으로 연다 — 외부 링크를 여는 것과 같은 취급이다.
    func editorBridge(_ bridge: EditorBridge, didRequestOpenAttachment payload: OpenAttachmentPayload) {
        do {
            let url = try attachmentStorage.url(attachmentId: payload.attachmentId, fileName: payload.fileName)
            NSWorkspace.shared.open(url)
        } catch {
            report(error)
        }
    }

    func editorBridge(_ bridge: EditorBridge, didReportError message: String) {
        errorMessage = message
    }
}
