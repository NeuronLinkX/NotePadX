import Foundation

/// 태그를 붙이지 않아도 노트끼리 자동으로 연관성을 찾는 알고리즘 (스펙: 신경망 이미지처럼
/// 키워드로 서로 알아서 찾아 이어 붙이는 시뮬레이션).
///
/// 1) 각 노트 본문을 3글자 트라이그램으로 쪼갠다 — SearchIndexService가 FTS5에 trigram
///    토크나이저를 쓰는 것과 같은 이유다: 한글은 띄어쓰기 단위 토큰화가 어절 경계를
///    놓치기 쉬워서, 언어에 무관하게 안정적으로 동작하는 문자 단위 n-gram을 쓴다.
/// 2) 트라이그램마다 TF-IDF(단어 빈도 × 역문서 빈도) 가중치를 계산한다. idf는 scikit-learn의
///    기본 "smooth idf"와 같은 식을 쓴다 — 분자·분모에 1을 더해 모든 문서에 나오는(df=N)
///    흔한 트라이그램도 idf가 0이 되지 않고(그러면 그 항이 통째로 사라져 버린다) 최소
///    가중치 1은 남게 한다:
///      tf(t, d)  = 문서 d에서 트라이그램 t가 나온 횟수
///      idf(t)    = ln((N + 1) / (df(t) + 1)) + 1     (N: 전체 문서 수, df(t): t가 등장한 문서 수)
///      w(t, d)   = tf(t, d) × idf(t)
/// 3) 두 노트 벡터의 코사인 유사도로 "얼마나 비슷한 어휘를 쓰는지"를 잰다:
///      cos(A, B) = (A·B) / (‖A‖ × ‖B‖)          범위: 0(전혀 안 겹침) ~ 1(똑같음)
/// 4) 유사도가 임계값 이상인 것 중, 노트마다 상위 K개 이웃만 연결선으로 남긴다 —
///    그렇지 않으면 그래프가 서로 다 이어진 실타래가 되어 어떤 군집도 안 보인다.
enum NoteSimilarityEngine {
    struct Edge: Identifiable, Equatable {
        var id: String { [from.uuidString, to.uuidString].sorted().joined(separator: "-") }
        let from: UUID
        let to: UUID
        /// 0...1 범위의 코사인 유사도.
        let weight: Double
    }

    /// 그래프가 감당할 수 있는 규모로만 계산한다 — O(N²) 비교이므로 메모 수천 개까지
    /// 전부 돌리면 부가 시각화 하나 때문에 편집기가 느려질 수 있다. 호출자가 이미
    /// updated_at 내림차순으로 넘겨주면 최근 메모가 우선 남는다.
    static let maxNotes = 150

    static func trigrams(of text: String) -> [String] {
        let normalized = text.lowercased().filter { !$0.isWhitespace }
        guard normalized.count >= 3 else { return normalized.isEmpty ? [] : [normalized] }
        let chars = Array(normalized)
        var grams: [String] = []
        grams.reserveCapacity(chars.count - 2)
        for i in 0...(chars.count - 3) {
            grams.append(String(chars[i..<(i + 3)]))
        }
        return grams
    }

    private static func tfidfVectors(for documents: [UUID: [String: Int]]) -> [UUID: [String: Double]] {
        let docCount = Double(documents.count)
        var documentFrequency: [String: Int] = [:]
        for (_, counts) in documents {
            for term in counts.keys { documentFrequency[term, default: 0] += 1 }
        }

        var vectors: [UUID: [String: Double]] = [:]
        for (id, counts) in documents {
            var vector: [String: Double] = [:]
            vector.reserveCapacity(counts.count)
            for (term, tf) in counts {
                let df = Double(documentFrequency[term] ?? 1)
                let idf = log((docCount + 1) / (df + 1)) + 1
                vector[term] = Double(tf) * idf
            }
            vectors[id] = vector
        }
        return vectors
    }

    private static func cosineSimilarity(_ a: [String: Double], _ b: [String: Double]) -> Double {
        let (smaller, larger) = a.count <= b.count ? (a, b) : (b, a)
        var dot = 0.0
        for (term, value) in smaller {
            if let other = larger[term] { dot += value * other }
        }
        let normA = sqrt(a.values.reduce(0) { $0 + $1 * $1 })
        let normB = sqrt(b.values.reduce(0) { $0 + $1 * $1 })
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA * normB)
    }

    /// notes: (id, plainText) 목록. minSimilarity 미만인 연결은 버리고, 노트 하나당
    /// maxNeighborsPerNote개까지만 남긴다(허브 노드가 너무 많은 선으로 뒤덮이지 않게).
    static func buildGraph(
        notes: [(id: UUID, text: String)],
        minSimilarity: Double = 0.08,
        maxNeighborsPerNote: Int = 4
    ) -> [Edge] {
        guard notes.count > 1 else { return [] }
        var termCounts: [UUID: [String: Int]] = [:]
        for note in notes {
            var counts: [String: Int] = [:]
            for gram in trigrams(of: note.text) { counts[gram, default: 0] += 1 }
            termCounts[note.id] = counts
        }
        let vectors = tfidfVectors(for: termCounts)
        let ids = notes.map(\.id)

        var seen = Set<String>()
        var edges: [Edge] = []
        for i in 0..<ids.count {
            guard let vi = vectors[ids[i]] else { continue }
            var candidates: [Edge] = []
            for j in 0..<ids.count where j != i {
                guard let vj = vectors[ids[j]] else { continue }
                let sim = cosineSimilarity(vi, vj)
                guard sim >= minSimilarity else { continue }
                candidates.append(Edge(from: ids[i], to: ids[j], weight: sim))
            }
            candidates.sort { $0.weight > $1.weight }
            for edge in candidates.prefix(maxNeighborsPerNote) {
                guard !seen.contains(edge.id) else { continue }
                seen.insert(edge.id)
                edges.append(edge)
            }
        }
        return edges
    }
}
