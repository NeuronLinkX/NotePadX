import Foundation

/// 에디터 영역의 분할 상태를 관리한다. 패널 두 개(primary/secondary)는 각각 완전히 독립된
/// EditorViewModel(따라서 독립된 WKWebView/Tiptap 인스턴스, 독립된 커서·스크롤·선택 상태)을 갖는다.
@MainActor
final class WorkspaceViewModel: ObservableObject {
    @Published var splitMode: SplitMode = .none
    @Published var splitRatio: Double
    @Published var secondaryNoteID: UUID?

    let primaryEditor: EditorViewModel
    let secondaryEditor: EditorViewModel

    private static let splitRatioDefaultsKey = "NotepadX.splitRatio"

    init(noteUseCase: NoteUseCase, tagUseCase: TagUseCase, revisionUseCase: NoteRevisionUseCase) {
        self.primaryEditor = EditorViewModel(noteUseCase: noteUseCase, tagUseCase: tagUseCase, revisionUseCase: revisionUseCase)
        self.secondaryEditor = EditorViewModel(noteUseCase: noteUseCase, tagUseCase: tagUseCase, revisionUseCase: revisionUseCase)
        let storedRatio = UserDefaults.standard.double(forKey: Self.splitRatioDefaultsKey)
        self.splitRatio = storedRatio > 0 ? storedRatio : 0.5
    }

    func setSplitRatio(_ value: Double) {
        splitRatio = value
        UserDefaults.standard.set(value, forKey: Self.splitRatioDefaultsKey)
    }

    func toggleHorizontalSplit(primaryNoteID: UUID?) {
        setSplitMode(splitMode == .horizontal ? .none : .horizontal, primaryNoteID: primaryNoteID)
    }

    func toggleVerticalSplit(primaryNoteID: UUID?) {
        setSplitMode(splitMode == .vertical ? .none : .vertical, primaryNoteID: primaryNoteID)
    }

    func closeSplit() {
        splitMode = .none
    }

    private func setSplitMode(_ mode: SplitMode, primaryNoteID: UUID?) {
        let wasSplit = splitMode.isSplit
        splitMode = mode
        // 분할을 처음 켤 때는 "같은 문서의 서로 다른 위치" 모드로 시작하는 게 자연스럽다.
        // 사용자가 오른쪽/아래 패널의 노트 선택 메뉴에서 다른 문서로 바꿀 수 있다.
        if mode.isSplit, !wasSplit {
            secondaryNoteID = primaryNoteID
        }
    }
}
