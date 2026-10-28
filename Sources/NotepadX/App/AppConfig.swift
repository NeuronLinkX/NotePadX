import Foundation

/// 앱 이름, Bundle ID, 표시 문자열을 한 곳에서 관리한다.
/// 이름을 바꾸고 싶으면 이 파일과 project.yml의 bundleIdPrefix/name만 수정하면 된다.
enum AppConfig {
    static let displayName = "NotepadX"
    static let bundleIdentifier = "com.notepadx.app"

    /// 개발·시연용 격리 프로필. 환경 변수 `NOTEPADX_PROFILE=demo`로 실행하면 데이터 폴더, 환경설정,
    /// Keychain 항목이 실사용 것과 완전히 분리된다 — 실제 메모를 건드리지 않고 백업/복원/마이그레이션
    /// 같은 위험한 동작을 시험하거나, 가짜 메모로 화면을 찍을 때 쓴다. 지정하지 않으면 평소와 같다.
    static let profile: String? = {
        let raw = ProcessInfo.processInfo.environment["NOTEPADX_PROFILE"] ?? ""
        let cleaned = raw.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return cleaned.isEmpty ? nil : cleaned
    }()

    static var isIsolatedProfile: Bool { profile != nil }

    /// ~/Library/Application Support/NotepadX (격리 프로필이면 NotepadX-<프로필>)
    static var applicationSupportDirectoryName: String {
        profile.map { "\(displayName)-\($0)" } ?? displayName
    }

    /// 환경설정 저장소. 격리 프로필이면 별도 도메인을 쓴다.
    static var defaults: UserDefaults {
        profile.flatMap { UserDefaults(suiteName: "\(bundleIdentifier).\($0)") } ?? .standard
    }

    static var keychainService: String {
        profile.map { "\(bundleIdentifier).\($0)" } ?? bundleIdentifier
    }

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
        if let existing = defaults.string(forKey: deviceIDDefaultsKey) {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: deviceIDDefaultsKey)
        return generated
    }
}
