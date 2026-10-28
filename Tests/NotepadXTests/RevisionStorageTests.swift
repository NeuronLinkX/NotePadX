import XCTest
@testable import NotepadX

final class RevisionStorageTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("NotepadXRevisionStorage-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: tempURL.path + suffix) }
    }

    // MARK: - 헬퍼

    /// base64에 `+`와 `/`가 확실히 들어가도록 무작위 바이트로 만든 이미지 data URI.
    private func imageURI(seed: UInt8, bytes: Int = 40_000) -> String {
        var generator = SeededGenerator(seed: UInt64(seed) &+ 1)
        let data = Data((0..<bytes).map { _ in UInt8.random(in: 0...255, using: &generator) })
        return "data:image/png;base64," + data.base64EncodedString()
    }

    private func document(uri: String, escapeSlashes: Bool, text: String = "본문") throws -> Data {
        let object: [String: Any] = [
            "type": "doc",
            "content": [
                ["type": "paragraph", "content": [["type": "text", "text": text]]],
                ["type": "image", "attrs": ["src": uri]],
            ],
        ]
        let options: JSONSerialization.WritingOptions = escapeSlashes ? [.sortedKeys] : [.sortedKeys, .withoutEscapingSlashes]
        return try JSONSerialization.data(withJSONObject: object, options: options)
    }

    private func makeRepo() async throws -> (DatabaseManager, SQLiteNoteRevisionRepository, UUID) {
        let db = try DatabaseManager(databaseURL: tempURL)
        try await SchemaMigrator.migrate(db)
        let noteUseCase = NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: SearchIndexService(db: db))
        let note = try await noteUseCase.createNote(folderID: nil)
        return (db, SQLiteNoteRevisionRepository(db: db), note.id)
    }

    private func count(_ db: DatabaseManager, _ sql: String) async throws -> Int {
        try await db.query(sql) { $0.int(0) ?? -1 }.first ?? -1
    }

    // MARK: - 코덱

    func testExtractAndHydrateAreLosslessForBothSlashEscapingStyles() throws {
        for escape in [true, false] {
            let json = String(decoding: try document(uri: imageURI(seed: 1), escapeSlashes: escape), as: UTF8.self)
            let extracted = RevisionBlobCodec.extract(from: json)

            XCTAssertEqual(extracted.blobs.count, 1)
            XCTAssertFalse(extracted.compacted.contains("data:image"), "이미지 본문이 참조로 바뀌어야 한다 (escape=\(escape))")
            XCTAssertLessThan(extracted.compacted.utf8.count, 1_000)
            XCTAssertEqual(RevisionBlobCodec.hydrate(extracted.compacted) { extracted.blobs[$0] }, json, "한 글자도 다르면 안 된다 (escape=\(escape))")
        }
    }

    /// 실제 사진은 base64로 수 MB다. 정규식 엔진은 이 정도 길이에서 오류 없이 "일치 없음"으로 실패했었다.
    func testMultiMegabyteImagesAreExtractedAndRestoredExactly() throws {
        let huge = imageURI(seed: 9, bytes: 3_500_000)   // base64 약 4.7MB
        for escape in [true, false] {
            let json = String(decoding: try document(uri: huge, escapeSlashes: escape), as: UTF8.self)
            let extracted = RevisionBlobCodec.extract(from: json)
            XCTAssertEqual(extracted.blobs.count, 1, "큰 이미지도 반드시 잡혀야 한다 (escape=\(escape))")
            XCTAssertLessThan(extracted.compacted.utf8.count, 1_000)
            XCTAssertEqual(RevisionBlobCodec.hydrate(extracted.compacted) { extracted.blobs[$0] }, json)
        }
    }

    func testImageRightAtTheEndOfTheDocumentAndBackToBackImages() {
        let a = imageURI(seed: 1, bytes: 3_000), b = imageURI(seed: 2, bytes: 3_000)
        let json = "{\"a\":\"\(a)\",\"b\":\"\(b)\"}" + "tail:" + a
        let extracted = RevisionBlobCodec.extract(from: json)
        XCTAssertEqual(extracted.blobs.count, 2)
        XCTAssertEqual(RevisionBlobCodec.hydrate(extracted.compacted) { extracted.blobs[$0] }, json)
    }

    func testMalformedDataURIsAreSkippedWithoutDamage() {
        let cases = ["data:image", "data:image/", "data:image/png;base64", "data:image/png;base64,", "x data:imagefoo y",
                     "data:image\\/;base64,AAAA"]
        for json in cases {
            let extracted = RevisionBlobCodec.extract(from: json)
            XCTAssertEqual(extracted.compacted, json)
            XCTAssertTrue(extracted.blobs.isEmpty)
        }
    }

    func testSmallImagesAndPlainDocumentsAreLeftAlone() {
        let small = #"{"src":"data:image/png;base64,iVBORw0KGgo="}"#
        XCTAssertEqual(RevisionBlobCodec.extract(from: small).compacted, small)
        XCTAssertTrue(RevisionBlobCodec.extract(from: small).blobs.isEmpty)
        let plain = #"{"type":"doc","content":[{"type":"paragraph"}]}"#
        XCTAssertEqual(RevisionBlobCodec.extract(from: plain).compacted, plain)
    }

    func testIdenticalImagesShareOneBlobAndHashesDifferForDifferentImages() throws {
        let a = imageURI(seed: 1), b = imageURI(seed: 2)
        let json = String(decoding: try document(uri: a, escapeSlashes: true), as: UTF8.self)
            + String(decoding: try document(uri: a, escapeSlashes: true), as: UTF8.self)
            + String(decoding: try document(uri: b, escapeSlashes: true), as: UTF8.self)
        let extracted = RevisionBlobCodec.extract(from: json)
        XCTAssertEqual(extracted.blobs.count, 2)
        XCTAssertEqual(RevisionBlobCodec.referencedHashes(in: extracted.compacted).count, 3)
    }

    func testMissingBlobReferencesAreKeptInsteadOfCrashing() {
        let json = "{\"src\":\"notepadx-blob:" + String(repeating: "a", count: 64) + "\"}"
        XCTAssertEqual(RevisionBlobCodec.hydrate(json) { _ in nil }, json)
    }

    func testStorageEncodingRoundTripsCompressedAndRawPayloads() {
        let text = imageURI(seed: 3)
        XCTAssertEqual(RevisionBlobCodec.decodeFromStorage(RevisionBlobCodec.encodeForStorage(text)), text)
        XCTAssertEqual(RevisionBlobCodec.decodeFromStorage(RevisionBlobCodec.encodeForStorage("a")), "a")
        XCTAssertNil(RevisionBlobCodec.decodeFromStorage(Data([9, 1, 2])))
        XCTAssertNil(RevisionBlobCodec.decodeFromStorage(Data()))
    }

    // MARK: - 저장소

    func testNewRevisionsStoreTheImageOnceAndReadBackIdentically() async throws {
        let (db, repo, noteID) = try await makeRepo()
        let original = try document(uri: imageURI(seed: 5), escapeSlashes: true)

        for index in 0..<5 {
            try await repo.createRevision(NoteRevision(noteID: noteID, documentJSON: original, plainText: "v\(index)", reason: .periodicEdit))
        }

        let blobCount = try await count(db, "SELECT COUNT(*) FROM revision_blob;")
        XCTAssertEqual(blobCount, 1, "같은 이미지는 다섯 번 저장돼도 한 벌만")
        let inline = try await count(db, "SELECT COUNT(*) FROM note_revision WHERE instr(document_json, 'data:image') > 0;")
        XCTAssertEqual(inline, 0, "DB에 저장된 버전 기록 본문에는 이미지가 없어야 한다")

        let revisions = try await repo.revisions(forNote: noteID)
        XCTAssertEqual(revisions.count, 5)
        for revision in revisions {
            XCTAssertEqual(revision.documentJSON, original, "읽을 때는 원본과 바이트까지 같아야 한다")
        }
        let single = try await repo.revision(id: revisions[0].id)
        XCTAssertEqual(single?.documentJSON, original)
    }

    func testRevisionsWithoutImagesAreStoredUntouched() async throws {
        let (db, repo, noteID) = try await makeRepo()
        let plain = Data(#"{"type":"doc","content":[]}"#.utf8)
        try await repo.createRevision(NoteRevision(noteID: noteID, documentJSON: plain, plainText: "", reason: .manualSnapshot))
        let stored = try await db.query("SELECT document_json FROM note_revision;") { $0.blob(0) }.first
        XCTAssertEqual(stored ?? nil, plain)
        let blobCount = try await count(db, "SELECT COUNT(*) FROM revision_blob;")
        XCTAssertEqual(blobCount, 0)
    }

    func testPruningRemovesBlobsNoRevisionReferencesAnymore() async throws {
        let (db, repo, noteID) = try await makeRepo()
        for seed in 0..<4 {
            let doc = try document(uri: imageURI(seed: UInt8(seed + 10)), escapeSlashes: true)
            try await repo.createRevision(NoteRevision(noteID: noteID, documentJSON: doc, plainText: "", reason: .periodicEdit, createdAt: Date(timeIntervalSince1970: Double(seed))))
        }
        let before = try await count(db, "SELECT COUNT(*) FROM revision_blob;")
        XCTAssertEqual(before, 4)

        try await repo.pruneOldRevisions(noteID: noteID, keep: 2)

        let revisions = try await count(db, "SELECT COUNT(*) FROM note_revision;")
        let blobs = try await count(db, "SELECT COUNT(*) FROM revision_blob;")
        XCTAssertEqual(revisions, 2)
        XCTAssertEqual(blobs, 2, "남은 기록 2개가 쓰는 이미지만 남아야 한다")
    }

    // MARK: - 기존 기록 정리

    private func insertLegacy(_ db: DatabaseManager, noteID: UUID, document: Data, id: UUID = UUID()) async throws {
        try await db.execute(
            "INSERT INTO note_revision (id, note_id, document_json, plain_text, reason, created_at) VALUES (?, ?, ?, '', 'periodicEdit', ?);",
            [.text(id.uuidString), .text(noteID.uuidString), .blob(document), .double(Date().timeIntervalSince1970)]
        )
    }

    func testCompactionShrinksLegacyRevisionsAndPreservesEveryByte() async throws {
        let (db, repo, noteID) = try await makeRepo()
        var originals: [UUID: Data] = [:]
        for index in 0..<12 {
            // 두 종류의 이미지를 섞고, 슬래시 이스케이프 방식도 섞는다.
            let doc = try document(uri: imageURI(seed: UInt8(index % 2)), escapeSlashes: index % 3 == 0, text: "문서 \(index % 2)")
            let id = UUID()
            originals[id] = doc
            try await insertLegacy(db, noteID: noteID, document: doc, id: id)
        }
        let before = try await RevisionStorageService.stats(db)
        XCTAssertEqual(before.inlineImageRevisionCount, 12)
        let needs = try await RevisionStorageService.needsCompaction(db)
        XCTAssertTrue(needs)

        let report = try await RevisionStorageService.compact(db)

        XCTAssertEqual(report.convertedRevisions, 12)
        XCTAssertLessThan(report.databaseBytesAfter, report.databaseBytesBefore / 3, "12벌이 2벌분으로 줄어야 한다")
        let after = try await RevisionStorageService.stats(db)
        XCTAssertEqual(after.inlineImageRevisionCount, 0)
        XCTAssertLessThan(after.revisionBytes, before.revisionBytes / 3)

        for revision in try await repo.revisions(forNote: noteID) {
            XCTAssertEqual(revision.documentJSON, originals[revision.id], "정리 후에도 모든 기록이 원본과 바이트까지 같아야 한다")
        }
        let blobs = try await count(db, "SELECT COUNT(*) FROM revision_blob;")
        XCTAssertLessThanOrEqual(blobs, 4, "서로 다른 (이미지, 이스케이프) 조합만큼만 저장")
    }

    func testCompactionIsIdempotent() async throws {
        let (db, _, noteID) = try await makeRepo()
        try await insertLegacy(db, noteID: noteID, document: try document(uri: imageURI(seed: 7), escapeSlashes: true))
        let first = try await RevisionStorageService.compact(db)
        let second = try await RevisionStorageService.compact(db)
        XCTAssertEqual(first.convertedRevisions, 1)
        XCTAssertEqual(second.convertedRevisions, 0)
        let needs = try await RevisionStorageService.needsCompaction(db)
        XCTAssertFalse(needs)
    }

    func testCompactionSkipsRevisionsThatAreNotValidUTF8() async throws {
        let (db, _, noteID) = try await makeRepo()
        var bad = Data("data:image/png;base64,".utf8) + Data(repeating: 0x41, count: 3000)
        bad.append(contentsOf: [0xFF, 0xFE, 0xFD])   // 유효하지 않은 UTF-8
        try await insertLegacy(db, noteID: noteID, document: bad)

        let report = try await RevisionStorageService.compact(db)

        XCTAssertEqual(report.convertedRevisions, 0)
        let stored = try await db.query("SELECT document_json FROM note_revision;") { $0.blob(0) }.first
        XCTAssertEqual(stored ?? nil, bad, "손상된 기록은 한 바이트도 바꾸지 않는다")
    }

    func testStatsReportCountsAndSizes() async throws {
        let (db, _, noteID) = try await makeRepo()
        try await insertLegacy(db, noteID: noteID, document: try document(uri: imageURI(seed: 8), escapeSlashes: true))
        let stats = try await RevisionStorageService.stats(db)
        XCTAssertEqual(stats.revisionCount, 1)
        XCTAssertEqual(stats.inlineImageRevisionCount, 1)
        XCTAssertGreaterThan(stats.revisionBytes, 40_000)
        XCTAssertGreaterThan(stats.databaseBytes, 0)
    }

    // MARK: - 실제 DB 사본 검증 (선택)

    /// 실제 사용자 DB의 **복사본**에서 정리를 돌려 본다. 환경 변수로 사본 경로를 줄 때만 실행되고,
    /// 원본은 절대 열지 않는다:  NOTEPADX_REAL_DB_COPY=/path/copy.sqlite swift test --filter testRealDatabaseCopy
    func testRealDatabaseCopyCompactsLosslessly() async throws {
        guard let path = ProcessInfo.processInfo.environment["NOTEPADX_REAL_DB_COPY"] else {
            throw XCTSkip("NOTEPADX_REAL_DB_COPY 가 없으면 건너뛴다.")
        }
        let url = URL(fileURLWithPath: path)
        XCTAssertTrue(url.path.contains("scratchpad") || url.path.contains("/tmp") || url.path.contains("/var/folders"), "원본이 아닌 임시 사본만 허용")
        let db = try DatabaseManager(databaseURL: url)
        try await SchemaMigrator.migrate(db)   // 앱이 첫 실행 때 하는 것과 같은 순서
        let repo = SQLiteNoteRevisionRepository(db: db)

        let noteIDs = try await db.query("SELECT DISTINCT note_id FROM note_revision;") { $0.string(0) ?? "" }
        var snapshot: [UUID: Data] = [:]
        for noteID in noteIDs.compactMap(UUID.init(uuidString:)) {
            for revision in try await repo.revisions(forNote: noteID) { snapshot[revision.id] = revision.documentJSON }
        }
        let before = try await RevisionStorageService.stats(db)
        print("REALDB before: db=\(before.databaseBytes / 1_048_576)MB revisions=\(before.revisionCount) inline=\(before.inlineImageRevisionCount) revisionBytes=\(before.revisionBytes / 1_048_576)MB")

        let report = try await RevisionStorageService.compact(db)

        let after = try await RevisionStorageService.stats(db)
        print("REALDB after:  db=\(after.databaseBytes / 1_048_576)MB converted=\(report.convertedRevisions) revisionBytes=\(after.revisionBytes / 1_048_576)MB saved=\(report.savedBytes / 1_048_576)MB")
        var mismatches = 0
        for noteID in noteIDs.compactMap(UUID.init(uuidString:)) {
            for revision in try await repo.revisions(forNote: noteID) where snapshot[revision.id] != revision.documentJSON { mismatches += 1 }
        }
        XCTAssertEqual(mismatches, 0, "실제 데이터의 모든 버전 기록이 정리 전과 바이트까지 같아야 한다")
        XCTAssertEqual(after.inlineImageRevisionCount, 0)
        let integrity = try await db.quickCheck()
        XCTAssertEqual(integrity, ["ok"])
    }
}

/// 같은 시드면 같은 바이트가 나오는 난수 생성기 — 테스트가 매번 똑같이 재현되게 한다.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
