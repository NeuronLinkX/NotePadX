import AppKit
import XCTest
@testable import NotepadX

/// 시연·스크린샷용 가짜 데이터를 격리 프로필(NOTEPADX_PROFILE)의 데이터 폴더에 채운다.
/// 평소 `swift test`에서는 건너뛰고, 아래처럼 환경 변수를 줄 때만 실행된다:
///   NOTEPADX_PROFILE=demo NOTEPADX_SEED_DEMO=1 swift test --filter DemoDataSeeder
/// 격리 프로필이 아니면 어떤 경우에도 실행을 거부한다 — 실제 메모를 지우면 안 되기 때문이다.
final class DemoDataSeeder: XCTestCase {
    func testSeedDemoProfile() async throws {
        guard ProcessInfo.processInfo.environment["NOTEPADX_SEED_DEMO"] == "1" else {
            throw XCTSkip("NOTEPADX_SEED_DEMO=1 일 때만 데모 데이터를 만든다.")
        }
        XCTAssertTrue(AppConfig.isIsolatedProfile, "격리 프로필(NOTEPADX_PROFILE)이 아니면 절대 시드하지 않는다")
        try XCTSkipUnless(AppConfig.isIsolatedProfile)

        let support = try AppConfig.applicationSupportURL()
        for name in try FileManager.default.contentsOfDirectory(atPath: support.path) {
            try? FileManager.default.removeItem(at: support.appendingPathComponent(name))
        }

        let dbURL = try AppConfig.databaseURL()
        let db = try DatabaseManager(databaseURL: dbURL)
        try await SchemaMigrator.migrate(db)
        let useCase = NoteUseCase(noteRepository: SQLiteNoteRepository(db: db), searchIndex: SearchIndexService(db: db))

        func heading(_ text: String, level: Int = 1) -> EditorNode {
            EditorNode(rawType: "heading", attrs: ["level": .number(Double(level))], content: [.textNode(text)])
        }
        func bullets(_ items: [String]) -> EditorNode {
            EditorNode(type: .bulletList, content: items.map { EditorNode(type: .listItem, content: [.paragraph($0)]) })
        }
        func plain(_ nodes: [EditorNode]) -> String { EditorDocument(content: nodes).derivedPlainText }

        let notes: [(String, [EditorNode], Bool)] = [
            ("주간 회의록 — 10월 4주차", [
                heading("주간 회의록 — 10월 4주차"),
                .paragraph("참석: 김하늘, 박서준, 이도윤, 최유나"),
                heading("논의 사항", level: 2),
                bullets(["신규 온보딩 화면 시안 확정", "백업 기능 출시 일정 조율 (11월 첫째 주)", "고객 문의 상위 3건 원인 분석"]),
                heading("다음 주 할 일", level: 2),
                bullets(["시안 최종 검수 — 하늘", "릴리즈 노트 초안 — 서준", "문의 분석 공유 — 유나"]),
            ], true),
            ("독서 메모: 클린 아키텍처", [
                heading("독서 메모: 클린 아키텍처"),
                .paragraph("의존성은 항상 안쪽(정책)을 향해야 한다. 프레임워크와 DB는 세부 사항일 뿐이다."),
                bullets(["경계를 가로지르는 데이터는 단순한 구조체로", "유스케이스가 앱의 중심", "테스트가 쉬워지는 것이 설계가 좋다는 신호"]),
            ], false),
            ("제주 여행 계획", [
                heading("제주 여행 계획 (3박 4일)"),
                bullets(["1일차: 김포 → 제주, 렌터카 수령, 애월 해안도로", "2일차: 성산일출봉, 섭지코지, 우도 배편 예약", "3일차: 한라산 영실 코스 (아침 일찍 출발)", "4일차: 동문시장 → 공항"]),
            ], false),
            ("아이디어 모음", [
                heading("아이디어 모음"),
                bullets(["메모 앱 위젯에서 바로 체크리스트 완료하기", "음성 메모 → 자동 요약", "주간 회고 템플릿 자동 생성"]),
            ], false),
            ("논문 읽기 — 분산 합의 알고리즘", [
                heading("논문 읽기 — 분산 합의 알고리즘"),
                .paragraph("Raft는 리더 선출, 로그 복제, 안전성의 세 부분으로 나누어 이해하기 쉽게 설계되었다."),
                bullets(["리더가 모든 쓰기를 순서대로 복제한다", "과반수 응답이 있어야 커밋된다", "리더 장애 시 임기(term)가 올라가며 재선출"]),
            ], false),
            ("장보기 목록", [
                heading("장보기 목록"),
                bullets(["우유, 달걀, 두부", "방울토마토, 아보카도", "올리브유, 파스타면", "세제, 키친타월"]),
            ], false),
            ("프로젝트 일정", [
                heading("프로젝트 일정"),
                bullets(["10월 31일 — 기능 동결", "11월 07일 — 베타 배포", "11월 21일 — 정식 출시"]),
            ], false),
        ]

        var base = Date().addingTimeInterval(-3 * 3600)
        for (title, nodes, favorite) in notes {
            var note = try await useCase.createNote(folderID: nil)
            note = try useCase.applyEdit(to: note, title: title, document: EditorDocument(content: nodes), plainText: plain(nodes))
            note.isFavorite = favorite
            note.updatedAt = base
            base = base.addingTimeInterval(-1800)
            try await useCase.save(note)
        }

        // 이미지가 든 메모 + 버전 기록 — 저장 공간 문제를 보여 주는 데이터. 버전 기록은 예전 방식(이미지가
        // 문서 안에 통째로 들어 있는 상태)을 그대로 흉내 내려고 SQL로 직접 넣는다.
        let imageData = Self.noisePNG(width: 700, height: 460)
        let dataURI = "data:image/png;base64," + imageData.base64EncodedString()
        let imageDoc = EditorDocument(content: [
            heading("현장 사진 정리"),
            .paragraph("아래는 어제 찍은 현장 사진입니다."),
            EditorNode(rawType: "image", attrs: ["src": .string(dataURI)]),
            .paragraph("메모: 오른쪽 상단 균열 확인 필요."),
        ])
        var imageNote = try await useCase.createNote(folderID: nil)
        imageNote = try useCase.applyEdit(to: imageNote, title: "현장 사진 정리", document: imageDoc, plainText: plain(imageDoc.content))
        imageNote.updatedAt = Date()
        try await useCase.save(imageNote)
        for index in 0..<14 {
            try await db.execute(
                "INSERT INTO note_revision (id, note_id, document_json, plain_text, reason, created_at) VALUES (?, ?, ?, ?, ?, ?);",
                [.text(UUID().uuidString), .text(imageNote.id.uuidString), .blob(imageNote.documentJSON),
                 .text(imageNote.plainText + " (\(index))"), .text("periodicEdit"),
                 .double(Date().addingTimeInterval(Double(-index) * 600).timeIntervalSince1970)]
            )
        }

        // 백업 목록이 비어 보이지 않도록 서로 다른 시각의 백업 몇 개.
        let clock = BackupClock(Date().addingTimeInterval(-2 * 86_400))
        let service = DatabaseBackupService(now: { clock.now })
        try await service.createBackup(from: db, kind: .manual)
        clock.advance(86_400)
        try await service.createBackup(from: db, kind: .auto)
        clock.advance(86_400 - 5_000)
        try await service.createBackup(from: db, kind: .auto)
    }

    /// 압축이 거의 안 되는 무작위 노이즈 PNG — 실제 사진처럼 용량이 큰 이미지를 흉내 낸다.
    private static func noisePNG(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32
        )!
        var generator = SystemRandomNumberGenerator()
        for index in 0..<(width * height * 4) {
            rep.bitmapData![index] = index % 4 == 3 ? 255 : UInt8.random(in: 0...255, using: &generator)
        }
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
