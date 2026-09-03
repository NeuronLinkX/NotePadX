import Foundation

enum AttachmentStorageError: LocalizedError {
    case invalidBase64
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidBase64: return "첨부파일 데이터를 읽을 수 없습니다."
        case .notFound: return "첨부파일을 찾을 수 없습니다. 원본이 이동되거나 삭제되었을 수 있습니다."
        }
    }
}

/// 이미지처럼 노트 JSON 안에 base64로 통째로 담기에는 너무 큰 일반 파일(PDF·문서·압축파일 등)을
/// `AppConfig.attachmentsDirectoryURL()` 아래 첨부 id별 폴더에 원본 파일명 그대로 저장한다.
/// 노트(EditorNode.attrs)에는 id·파일명·크기·MIME 타입만 참조로 남고, 실제 바이트는 여기서만
/// 관리한다 — 폴더를 id로 나누는 이유는 같은 이름의 파일을 여러 번 첨부해도 서로 덮어쓰지
/// 않으면서, 그 폴더를 열어 보면(Finder에서 아이콘 형태로) 원본 그대로의 파일명이 보이게
/// 하기 위해서다.
struct AttachmentStorage: Sendable {
    /// 기본값은 실제 앱 저장 위치(`AppConfig.attachmentsDirectoryURL`)이지만, 테스트에서는
    /// 임시 디렉터리를 주입해 실제 사용자의 Application Support를 건드리지 않는다 —
    /// DatabaseManager(databaseURL:)와 같은 패턴이다.
    private let baseDirectoryProvider: @Sendable () throws -> URL

    init(baseDirectoryProvider: @escaping @Sendable () throws -> URL = { try AppConfig.attachmentsDirectoryURL() }) {
        self.baseDirectoryProvider = baseDirectoryProvider
    }

    @discardableResult
    func save(attachmentId: String, fileName: String, base64Data: String) throws -> URL {
        guard let data = Data(base64Encoded: base64Data) else { throw AttachmentStorageError.invalidBase64 }
        let directory = try directoryURL(attachmentId: attachmentId)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(FileNameSanitizer.sanitize(fileName, fallback: "첨부파일"))
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    func url(attachmentId: String, fileName: String) throws -> URL {
        let fileURL = try directoryURL(attachmentId: attachmentId)
            .appendingPathComponent(FileNameSanitizer.sanitize(fileName, fallback: "첨부파일"))
        guard FileManager.default.fileExists(atPath: fileURL.path) else { throw AttachmentStorageError.notFound }
        return fileURL
    }

    private func directoryURL(attachmentId: String) throws -> URL {
        // attachmentId는 JS의 crypto.randomUUID()로 만들어지지만, 방어적으로 경로 구분자를
        // 한 번 더 걸러낸다 — 신뢰할 수 없는 값이 그대로 경로 컴포넌트가 되지 않게 한다.
        let safeId = FileNameSanitizer.sanitize(attachmentId, fallback: "attachment")
        return try baseDirectoryProvider().appendingPathComponent(safeId, isDirectory: true)
    }
}
