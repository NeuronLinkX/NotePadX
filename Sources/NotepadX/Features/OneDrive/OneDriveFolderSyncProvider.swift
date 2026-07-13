import Foundation

/// download(id:)가 "원격에 아직 없음"과 "원격 데이터가 손상됨"을 구분해서 던지는 오류.
/// OneDriveSyncUseCase는 전자일 때만 초기 업로드로 취급하고, 후자는 진짜 오류로 사용자에게 알린다
/// — 그렇지 않으면 손상된 원격 패키지를 "없는 것"으로 착각해 조용히 덮어쓸 위험이 있다.
enum SyncProviderError: LocalizedError, Sendable {
    case notFound
    case corrupted(String)

    var errorDescription: String? {
        switch self {
        case .notFound: return "원격에 해당 노트가 없습니다."
        case .corrupted(let id): return "원격 노트(\(id))의 데이터가 손상되어 읽을 수 없습니다."
        }
    }
}

private struct SyncMetadata: Codable {
    var noteID: UUID
    var title: String
    var updatedAt: Date
    var contentHash: String
    var deviceID: String
}

private enum SyncJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// 스펙 13.1절: OneDrive(또는 그 하위) 동기화 폴더에 노트를
/// `<uuid>.notepadx/document.json` + `metadata.json` 패키지로 저장한다.
///
/// `@MainActor`가 아닌 평범한 Sendable struct다 — `NSFileCoordinator`는 동기(블로킹) API라
/// OneDrive가 파일을 아직 다운로드하지 않은 상태(placeholder)면 시간이 걸릴 수 있는데,
/// 이 타입을 메인 액터에 묶지 않아야 그 블로킹이 UI 스레드를 막지 않는다. 폴더 URL은
/// 호출 시점에 FolderAccessService(메인 액터)에서 한 번 읽어 불변 값으로 넘겨받는다.
struct OneDriveFolderSyncProvider: CloudSyncProvider {
    let rootURL: URL
    let deviceID: String

    /// 폴더 접근 자체는 FolderAccessService가 관리하므로 여기서는 아무것도 하지 않는다.
    func authenticate() async throws {}
    func signOut() async throws {}

    func listNotes() async throws -> [RemoteNote] {
        var result: [RemoteNote] = []
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: rootURL, options: [], error: &coordinatorError) { url in
            guard let entries = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
            for entry in entries where entry.pathExtension == "notepadx" {
                guard let data = try? Data(contentsOf: entry.appendingPathComponent("metadata.json")),
                      let metadata = try? SyncJSON.decoder.decode(SyncMetadata.self, from: data) else { continue }
                result.append(RemoteNote(id: metadata.noteID.uuidString, title: metadata.title, updatedAt: metadata.updatedAt, contentHash: metadata.contentHash))
            }
        }
        if let coordinatorError { throw coordinatorError }
        return result
    }

    func upload(_ note: SyncDocument) async throws {
        let packageURL = packageURL(for: note.noteID.uuidString)
        var coordinatorError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: packageURL, options: .forReplacing, error: &coordinatorError) { url in
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: url.appendingPathComponent("attachments"), withIntermediateDirectories: true)
                try note.documentJSON.write(to: url.appendingPathComponent("document.json"), options: .atomic)
                let metadata = SyncMetadata(noteID: note.noteID, title: note.title, updatedAt: note.updatedAt, contentHash: note.contentHash, deviceID: note.deviceID)
                let metadataData = try SyncJSON.encoder.encode(metadata)
                try metadataData.write(to: url.appendingPathComponent("metadata.json"), options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let writeError { throw writeError }
    }

    func download(id: String) async throws -> SyncDocument {
        let packageURL = packageURL(for: id)
        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            throw SyncProviderError.notFound
        }

        var result: SyncDocument?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: packageURL, options: [], error: &coordinatorError) { url in
            guard let documentData = try? Data(contentsOf: url.appendingPathComponent("document.json")),
                  let metadataData = try? Data(contentsOf: url.appendingPathComponent("metadata.json")),
                  let metadata = try? SyncJSON.decoder.decode(SyncMetadata.self, from: metadataData) else { return }
            let document = (try? EditorDocument.decode(from: documentData)) ?? .fromPlainText("")
            result = SyncDocument(
                noteID: metadata.noteID,
                title: metadata.title,
                documentJSON: documentData,
                plainText: document.derivedPlainText,
                updatedAt: metadata.updatedAt,
                contentHash: metadata.contentHash,
                baseRevision: nil,
                deviceID: metadata.deviceID
            )
        }
        if let coordinatorError { throw coordinatorError }
        guard let result else { throw SyncProviderError.corrupted(id) }
        return result
    }

    func delete(id: String) async throws {
        let packageURL = packageURL(for: id)
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: packageURL, options: .forDeleting, error: &coordinatorError) { url in
            try? FileManager.default.removeItem(at: url)
        }
        if let coordinatorError { throw coordinatorError }
    }

    private func packageURL(for noteID: String) -> URL {
        rootURL.appendingPathComponent("\(noteID).notepadx", isDirectory: true)
    }
}
