import Foundation

/// 브라우저처럼 한 창 안에서 여러 메모를 탭으로 열어 둔 상태를 관리한다 (스펙: 다중 탭 지원).
/// "지금 화면에 보이는 메모"의 단일 진실 공급원은 여전히 NoteListViewModel.selectedNoteID이고,
/// 이 뷰모델은 그 값이 바뀔 때마다 탭 목록에 추가하고, 탭 UI(제목 표시/닫기)만 담당한다.
@MainActor
final class OpenTabsViewModel: ObservableObject {
    @Published private(set) var openNoteIDs: [UUID] = []
    @Published private(set) var titles: [UUID: String] = [:]

    private let noteUseCase: NoteUseCase

    init(noteUseCase: NoteUseCase) {
        self.noteUseCase = noteUseCase
    }

    /// 노트가 화면에 보이게 될 때마다 호출한다. 이미 열린 탭이면 아무 일도 하지 않고,
    /// 제목만 알고 있으면(목록/검색 결과에서 이미 로드됨) 그 자리에서 갱신한다.
    func noteOpened(_ id: UUID?, knownTitle: String? = nil) {
        guard let id else { return }
        if let knownTitle { titles[id] = knownTitle }
        guard !openNoteIDs.contains(id) else { return }
        openNoteIDs.append(id)
        if titles[id] == nil {
            Task { [noteUseCase] in
                guard let note = try? await noteUseCase.fetchNote(id: id) else { return }
                self.titles[id] = note.displayTitle
            }
        }
    }

    /// 저장 등으로 제목이 바뀌었을 때 탭 이름도 같이 갱신한다.
    func updateTitle(_ id: UUID, title: String) {
        guard openNoteIDs.contains(id) else { return }
        titles[id] = title
    }

    /// 탭을 닫는다. 닫은 탭이 활성 탭이었다면, 그다음에 활성화해야 할 노트 id를 돌려준다
    /// (없으면 nil — 열린 탭이 하나도 안 남았다는 뜻).
    @discardableResult
    func closeTab(_ id: UUID, activeNoteID: UUID?) -> UUID? {
        guard let index = openNoteIDs.firstIndex(of: id) else { return activeNoteID }
        openNoteIDs.remove(at: index)
        titles[id] = nil
        guard activeNoteID == id else { return activeNoteID }
        guard !openNoteIDs.isEmpty else { return nil }
        return openNoteIDs[min(index, openNoteIDs.count - 1)]
    }
}
