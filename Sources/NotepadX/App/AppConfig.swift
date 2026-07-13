import Foundation

/// 앱 이름, Bundle ID, 표시 문자열을 한 곳에서 관리한다.
/// 이름을 바꾸고 싶으면 이 파일과 project.yml의 bundleIdPrefix/name만 수정하면 된다.
enum AppConfig {
    static let displayName = "NotepadX"
    static let bundleIdentifier = "com.notepadx.app"

    /// ~/Library/Application Support/NotepadX
    static let applicationSupportDirectoryName = displayName

    static let databaseFileName = "NotepadX.sqlite"
    static let attachmentsDirectoryName = "Attachments"

    static func applicationSupportURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func databaseURL() throws -> URL {
        try applicationSupportURL().appendingPathComponent(databaseFileName, isDirectory: false)
    }

    static func attachmentsDirectoryURL() throws -> URL {
        let directory = try applicationSupportURL().appendingPathComponent(attachmentsDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private static let deviceIDDefaultsKey = "NotepadX.deviceID"

    /// 동기화 메타데이터에 쓰는 이 기기의 식별자. 비밀값이 아니라 UserDefaults에 저장해도 된다.
    static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIDDefaultsKey) {
            return existing
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: deviceIDDefaultsKey)
        return generated
    }
}
