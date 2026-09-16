import Foundation
import SwiftUI

/// "연관 메모" 패널(스펙: 태그 없이도 신경망 이미지처럼 키워드로 서로 알아서 찾아 이어
/// 붙이는 시뮬레이션)의 상태. NoteSimilarityEngine이 계산한 연결선을 힘 기반(스프링+반발력)
/// 레이아웃으로 자리 잡게 해서, 비슷한 어휘를 쓰는 노트끼리 자연히 뭉치는 모습을 보여준다.
@MainActor
final class NoteGraphViewModel: ObservableObject {
    struct Node: Identifiable {
        let id: UUID
        var title: String
        var position: CGPoint
        var velocity: CGVector = .zero
    }

    @Published var isVisible = false
    @Published private(set) var nodes: [Node] = []
    @Published private(set) var edges: [NoteSimilarityEngine.Edge] = []
    @Published private(set) var isComputing = false

    private let noteUseCase: NoteUseCase
    private var simulationTask: Task<Void, Never>?

    /// 힘 기반 레이아웃 상수. Fruchterman–Reingold류: 모든 노드 쌍은 거리 제곱에 반비례해
    /// 서로 밀어내고, 연결된 노드끼리는 훅의 법칙처럼 목표 거리로 당긴다.
    private enum Physics {
        static let repulsionStrength = 12000.0
        static let springLength = 110.0
        static let springStrength = 0.02
        static let damping = 0.85
        static let stepCount = 220
        static let stepInterval: UInt64 = 16_000_000 // ~60fps
    }

    init(noteUseCase: NoteUseCase) {
        self.noteUseCase = noteUseCase
    }

    /// 패널을 열고 닫는다. 실제 계산은 패널 뷰가 나타날 때(`.onAppear`, 그때서야 실제
    /// 캔버스 크기를 알 수 있다) 호출하는 rebuild(canvasSize:)가 맡는다.
    func toggle() {
        isVisible.toggle()
    }

    /// 노트 본문이 바뀔 때마다(예: 저장 직후) 다시 계산해서 최신 연관 관계를 보여준다.
    func rebuild(canvasSize: CGSize) async {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        isComputing = true
        defer { isComputing = false }
        do {
            let notes = try await noteUseCase.fetchNotes(filter: .all, sortOrder: .updatedDescending)
            let candidates = notes.prefix(NoteSimilarityEngine.maxNotes)
                .filter { !$0.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let edges = NoteSimilarityEngine.buildGraph(notes: candidates.map { ($0.id, $0.plainText) })
            let connectedIDs = Set(edges.flatMap { [$0.from, $0.to] })
            let relevantNotes = candidates.filter { connectedIDs.contains($0.id) }

            let previousPositions = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })
            self.edges = edges
            self.nodes = relevantNotes.map { note in
                let position = previousPositions[note.id] ?? CGPoint(
                    x: .random(in: canvasSize.width * 0.2...max(canvasSize.width * 0.8, canvasSize.width * 0.2 + 1)),
                    y: .random(in: canvasSize.height * 0.2...max(canvasSize.height * 0.8, canvasSize.height * 0.2 + 1))
                )
                return Node(id: note.id, title: note.displayTitle, position: position)
            }
            runSimulation(canvasSize: canvasSize)
        } catch {
            // 이 패널은 부가 시각화라, 실패해도 편집 자체를 막지 않고 조용히 비워 둔다.
            edges = []
            nodes = []
        }
    }

    private func runSimulation(canvasSize: CGSize) {
        simulationTask?.cancel()
        simulationTask = Task { [weak self] in
            for _ in 0..<Physics.stepCount {
                guard let self, !Task.isCancelled else { return }
                self.step(canvasSize: canvasSize)
                try? await Task.sleep(nanoseconds: Physics.stepInterval)
            }
        }
    }

    private func step(canvasSize: CGSize) {
        guard nodes.count > 1 else { return }
        var forces = [UUID: CGVector](minimumCapacity: nodes.count)
        for node in nodes { forces[node.id] = .zero }

        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                let a = nodes[i], b = nodes[j]
                let dx = a.position.x - b.position.x
                let dy = a.position.y - b.position.y
                let distSq = max(dx * dx + dy * dy, 25)
                let dist = sqrt(distSq)
                let force = Physics.repulsionStrength / distSq
                let fx = (dx / dist) * force
                let fy = (dy / dist) * force
                forces[a.id]?.dx += fx; forces[a.id]?.dy += fy
                forces[b.id]?.dx -= fx; forces[b.id]?.dy -= fy
            }
        }

        let indexByID = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        for edge in edges {
            guard let ai = indexByID[edge.from], let bi = indexByID[edge.to] else { continue }
            let a = nodes[ai], b = nodes[bi]
            let dx = b.position.x - a.position.x
            let dy = b.position.y - a.position.y
            let dist = max(sqrt(dx * dx + dy * dy), 1)
            let displacement = dist - Physics.springLength
            let force = displacement * Physics.springStrength * edge.weight
            let fx = (dx / dist) * force
            let fy = (dy / dist) * force
            forces[a.id]?.dx += fx; forces[a.id]?.dy += fy
            forces[b.id]?.dx -= fx; forces[b.id]?.dy -= fy
        }

        for i in nodes.indices {
            guard let force = forces[nodes[i].id] else { continue }
            var velocity = nodes[i].velocity
            velocity.dx = (velocity.dx + force.dx) * Physics.damping
            velocity.dy = (velocity.dy + force.dy) * Physics.damping
            nodes[i].velocity = velocity
            var position = nodes[i].position
            position.x = min(max(position.x + velocity.dx, 24), max(canvasSize.width - 24, 24))
            position.y = min(max(position.y + velocity.dy, 24), max(canvasSize.height - 24, 24))
            nodes[i].position = position
        }
    }
}
