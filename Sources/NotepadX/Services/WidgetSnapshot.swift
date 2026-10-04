import Foundation

// 앱과 위젯 확장이 함께 컴파일하는 파일이다(project.yml의 NotepadXWidget 소스에도 이 파일이
// 직접 들어간다) — Foundation 외에는 아무것도 import하지 않는다.

struct WidgetNoteSummary: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let preview: String
    let updatedAt: Date
    let isFavorite: Bool
    let isPinned: Bool
}

struct WidgetSnapshot: Codable, Equatable, Sendable {
    let generatedAt: Date
    let notes: [WidgetNoteSummary]
}

/// 위젯은 별도 샌드박스 프로세스라 앱 컨테이너의 DB를 열 수 없다. 앱이 최근 메모 요약만
/// 담은 작은 JSON을 이 폴더에 쓰고, 위젯이 읽기 전용으로 읽는다. App Group은 팀 ID가 있는
/// 프로비저닝이 필요한데 이 앱은 ad-hoc 서명이라, 양쪽 entitlements에 같은 홈 상대 경로
/// 예외(temporary-exception)를 줘서 공유한다.
enum WidgetSnapshotStore {
    static let directoryName = "NotepadXWidget"
    static let fileName = "recent-notes.json"
    /// entitlements의 home-relative-path 값과 반드시 같아야 한다.
    static let homeRelativePath = "/Library/Application Support/NotepadXWidget/"

    /// 샌드박스 안에서 NSHomeDirectory()는 컨테이너를 돌려주므로, 실제 홈은 passwd에서 읽는다.
    static func realHomeDirectory() -> URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    static func defaultDirectoryURL() -> URL {
        realHomeDirectory()
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static func write(_ snapshot: WidgetSnapshot, to directory: URL = defaultDirectoryURL()) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    static func read(from directory: URL = defaultDirectoryURL()) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}

/// 위젯에서 앱으로 넘어오는 `notepadx://` 링크.
enum WidgetDeepLink: Equatable {
    case openNote(UUID)
    case newNote

    static let scheme = "notepadx"

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch url.host {
        case "new":
            self = .newNote
        case "note":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            self = .openNote(id)
        default:
            return nil
        }
    }

    static func url(forNote id: UUID) -> URL {
        URL(string: "\(scheme)://note/\(id.uuidString)")!
    }

    static var newNoteURL: URL { URL(string: "\(scheme)://new")! }
}
