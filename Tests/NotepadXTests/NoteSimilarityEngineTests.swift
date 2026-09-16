import XCTest
@testable import NotepadX

/// NoteSimilarityEngine의 TF-IDF + 코사인 유사도 알고리즘(스펙: 태그 없이 신경망 이미지처럼
/// 키워드로 서로 알아서 찾아 이어 붙이는 시뮬레이션의 수학적 근거)을 검증한다.
final class NoteSimilarityEngineTests: XCTestCase {
    func testTrigramsSplitsTextIntoOverlappingThreeCharacterWindows() {
        XCTAssertEqual(NoteSimilarityEngine.trigrams(of: "abcde"), ["abc", "bcd", "cde"])
    }

    func testTrigramsOfVeryShortTextReturnsTheWholeStringAsOneGram() {
        XCTAssertEqual(NoteSimilarityEngine.trigrams(of: "ab"), ["ab"])
    }

    func testTrigramsOfEmptyTextReturnsEmpty() {
        XCTAssertTrue(NoteSimilarityEngine.trigrams(of: "").isEmpty)
    }

    func testTrigramsIgnoresWhitespaceSoWordBoundariesDoNotBreakMatches() {
        // 한글은 띄어쓰기 단위 토큰화가 불안정해서 공백을 제거하고 트라이그램을 낸다 —
        // "가 나다"와 "가나다"가 같은 트라이그램 집합을 내야 한다.
        XCTAssertEqual(NoteSimilarityEngine.trigrams(of: "가 나다"), NoteSimilarityEngine.trigrams(of: "가나다"))
    }

    func testNotesSharingVocabularyGetConnectedWithHighWeight() {
        let a = UUID(), b = UUID(), c = UUID()
        let notes: [(id: UUID, text: String)] = [
            (a, "회의록: 프로젝트 일정과 예산을 논의했다. 다음 회의는 다음 주다."),
            (b, "프로젝트 일정과 예산 관련 후속 회의록. 다음 주에 다시 모인다."),
            (c, "오늘 저녁 메뉴는 파스타와 샐러드였다."),
        ]

        let edges = NoteSimilarityEngine.buildGraph(notes: notes, minSimilarity: 0.05, maxNeighborsPerNote: 4)

        guard let abEdge = edges.first(where: { Set([$0.from, $0.to]) == Set([a, b]) }) else {
            return XCTFail("어휘가 많이 겹치는 두 노트는 연결되어야 한다")
        }
        XCTAssertGreaterThan(abEdge.weight, 0.2)
        XCTAssertFalse(edges.contains { Set([$0.from, $0.to]) == Set([a, c]) }, "전혀 다른 주제의 노트끼리는 연결되면 안 된다")
        XCTAssertFalse(edges.contains { Set([$0.from, $0.to]) == Set([b, c]) })
    }

    func testMinSimilarityThresholdFiltersOutWeakMatches() {
        let a = UUID(), b = UUID()
        let notes: [(id: UUID, text: String)] = [
            (a, "완전히 서로 다른 내용의 문서 하나."),
            (b, "전혀 상관없는 두 번째 문서 내용."),
        ]
        let edges = NoteSimilarityEngine.buildGraph(notes: notes, minSimilarity: 0.99, maxNeighborsPerNote: 4)
        XCTAssertTrue(edges.isEmpty, "임계값을 아주 높게 잡으면 약한 연결은 모두 걸러져야 한다")
    }

    /// maxNeighborsPerNote는 "각 노트 자신의 관점에서" 상위 K개만 후보로 남긴다는 뜻이다
    /// (다른 노트가 이 노트를 자기 상위 K 안에 넣는 것까지 막지는 않는다 — 그건 정상적인
    /// k-최근접 이웃 그래프의 특성이다). 그래서 이 캡이 실제로 작동하는지는, 완전히
    /// 동등한 후보들 사이에서 한 노트가 스스로 고르는 개수가 K를 넘지 않는지로 확인한다.
    func testMaxNeighborsPerNoteLimitsHowManyCandidatesASingleNoteContributes() {
        let center = UUID()
        let neighbors = (0..<6).map { _ in UUID() }
        var notes: [(id: UUID, text: String)] = [(center, "공통키워드반복문장입니다")]
        for (index, neighbor) in neighbors.enumerated() {
            // 이웃마다 조금씩 다른 접미사를 붙여 서로 동점이 되지 않게 한다.
            notes.append((neighbor, "공통키워드반복문장입니다" + String(repeating: "z", count: index)))
        }

        let looseEdges = NoteSimilarityEngine.buildGraph(notes: notes, minSimilarity: 0.01, maxNeighborsPerNote: 6)
        let tightEdges = NoteSimilarityEngine.buildGraph(notes: notes, minSimilarity: 0.01, maxNeighborsPerNote: 1)

        XCTAssertLessThanOrEqual(tightEdges.count, looseEdges.count, "이웃 상한을 낮추면 전체 연결선 수도 줄거나 같아야 한다")
        XCTAssertGreaterThan(looseEdges.count, tightEdges.count, "이 시나리오에서는 상한을 낮추면 실제로 줄어들어야 한다")
    }

    func testSingleNoteProducesNoEdges() {
        let edges = NoteSimilarityEngine.buildGraph(notes: [(UUID(), "혼자 있는 노트")])
        XCTAssertTrue(edges.isEmpty)
    }

    func testEmptyNoteListProducesNoEdges() {
        XCTAssertTrue(NoteSimilarityEngine.buildGraph(notes: []).isEmpty)
    }
}
