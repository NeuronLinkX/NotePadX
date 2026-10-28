import Foundation

struct AppleNoteRaw: Sendable, Equatable {
    let title: String
    let html: String
}

enum AppleNotesError: Error, CustomStringConvertible {
    case notAuthorized
    case scriptFailed(String)

    var description: String {
        switch self {
        case .notAuthorized:
            return "메모 앱을 제어할 권한이 없습니다. 시스템 설정 > 개인정보 보호 및 보안 > 자동화에서 Notepad가 '메모'를 제어하도록 허용해 주세요"
        case .scriptFailed(let detail):
            return "메모 앱에서 가져오지 못했습니다 (\(detail))"
        }
    }
}

protocol AppleNotesFetching: Sendable {
    func fetchNotes() async throws -> [AppleNoteRaw]
}

/// 메모 앱에 AppleScript로 묻는다. 처음 쓸 때 macOS가 "NotepadX가 메모를 제어하려 합니다" 확인 창을 띄운다.
/// 암호로 잠긴 메모와 "최근 삭제된 항목"은 가져오지 않는다. 읽기만 하며 메모 앱의 내용은 바꾸지 않는다.
struct SystemAppleNotesFetcher: AppleNotesFetching {
    static let script = """
    tell application "Notes"
        set output to {}
        repeat with theFolder in folders
            set folderName to name of theFolder
            if folderName is not "Recently Deleted" and folderName is not "최근 삭제된 항목" then
                repeat with theNote in notes of theFolder
                    if not (password protected of theNote) then
                        set end of output to {name of theNote, body of theNote}
                    end if
                end repeat
            end if
        end repeat
        return output
    end tell
    """

    func fetchNotes() async throws -> [AppleNoteRaw] {
        try await withCheckedThrowingContinuation { continuation in
            // AppleScript 실행은 오래 걸릴 수 있으므로 메인 스레드 밖에서 한다.
            DispatchQueue.global(qos: .userInitiated).async {
                var errorInfo: NSDictionary?
                guard let script = NSAppleScript(source: Self.script) else {
                    continuation.resume(throwing: AppleNotesError.scriptFailed("스크립트를 만들지 못했습니다"))
                    return
                }
                let result = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let number = errorInfo[NSAppleScript.errorNumber] as? Int
                    if number == -1743 {   // errAEEventNotPermitted
                        continuation.resume(throwing: AppleNotesError.notAuthorized)
                    } else {
                        continuation.resume(throwing: AppleNotesError.scriptFailed(errorInfo[NSAppleScript.errorMessage] as? String ?? "알 수 없는 오류"))
                    }
                    return
                }
                continuation.resume(returning: Self.parse(result))
            }
        }
    }

    static func parse(_ descriptor: NSAppleEventDescriptor) -> [AppleNoteRaw] {
        guard descriptor.numberOfItems > 0 else { return [] }
        var notes: [AppleNoteRaw] = []
        for index in 1...descriptor.numberOfItems {
            guard let item = descriptor.atIndex(index), item.numberOfItems >= 2 else { continue }
            let title = item.atIndex(1)?.stringValue ?? ""
            let html = item.atIndex(2)?.stringValue ?? ""
            notes.append(AppleNoteRaw(title: title, html: html))
        }
        return notes
    }
}
