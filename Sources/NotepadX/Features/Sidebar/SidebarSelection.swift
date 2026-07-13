import Foundation

enum SidebarSelection: Hashable, Sendable {
    case all
    case recent
    case favorites
    case trash
    case folder(UUID)
    case tag(UUID)

    var noteListFilter: NoteListFilter {
        switch self {
        case .all: return .all
        case .recent: return .recent
        case .favorites: return .favorites
        case .trash: return .trash
        case .folder(let id): return .folder(id)
        case .tag(let id): return .tag(id)
        }
    }

    var title: String {
        switch self {
        case .all: return "모든 메모"
        case .recent: return "최근 메모"
        case .favorites: return "즐겨찾기"
        case .trash: return "휴지통"
        case .folder: return "폴더"
        case .tag: return "태그"
        }
    }
}
