import Foundation
import SwiftUI

/// "연관 메모" 패널(스펙: 태그 없이도 신경망 이미지처럼 3D로 애니메이팅되며 키워드로 서로
/// 알아서 찾아 이어 붙이는 시뮬레이션)의 상태. NoteSimilarityEngine이 계산한 연결선을
/// 3D 힘 기반(스프링+반발력) 레이아웃으로 자리 잡게 해서, 비슷한 어휘를 쓰는 노트끼리
/// 자연히 뭉치는 모습을 보여준다. 실제 3D 렌더링은 NoteGraph3DView(SceneKit)가 맡는다.
@MainActor
final class NoteGraphViewModel: ObservableObject {
    struct Vector3: Equatable {
        var x: Double = 0
        var y: Double = 0
        var z: Double = 0
    }

    struct Node: Identifiable {
        let id: UUID
        var title: String
        var position: Vector3
        var velocity: Vector3 = Vector3()
    }

    @Published var isVisible = false
    @Published private(set) var nodes: [Node] = []
    @Published private(set) var edges: [NoteSimilarityEngine.Edge] = []
    @Published private(set) var isComputing = false

    /// 지금 사용자가 마우스로 드래그 중인 노드. 시뮬레이션은 이 노드의 위치를 덮어쓰지
    /// 않고 그대로 둔다(사용자 손이 물리 연산을 이긴다) — 그 대신 나머지 노드들은 이
    /// 노드가 옮겨진 새 위치를 계속 힘 계산에 반영해 자연스럽게 따라 반응한다.
    private(set) var pinnedNodeID: UUID?

    private let noteUseCase: NoteUseCase
    private var simulationTask: Task<Void, Never>?

    /// 힘 기반 3D 레이아웃 상수 (Fruchterman–Reingold류). 초기 위치를 x·y·z 세 축 모두
    /// 무작위로 뿌려야 한 평면에 눌어붙지 않고 실제 입체로 퍼진다 — 대칭인 힘만으로는
    /// z=0에서 시작한 노드를 평면 밖으로 밀어낼 성분이 없기 때문이다.
    private enum Physics {
        static let repulsionStrength = 900.0
        static let springLength = 16.0
        static let springStrength = 0.03
        static let damping = 0.82
        static let spreadRadius = 34.0
        static let boundsRadius = 60.0
        static let stepInterval: UInt64 = 16_000_000 // ~60fps
    }

    init(noteUseCase: NoteUseCase) {
        self.noteUseCase = noteUseCase
    }

    /// "연관 메모" 창이 열렸다. 실제 계산은 창의 뷰가 나타날 때(`.onAppear`) 호출하는
    /// rebuild(canvasSize:)가 맡는다.
    func markVisible() {
        isVisible = true
    }

    /// 창이 닫혔다 — 보이지 않는 동안 불필요하게 CPU를 쓰지 않도록 시뮬레이션을 멈춘다.
    func markHidden() {
        isVisible = false
        simulationTask?.cancel()
        simulationTask = nil
    }

    /// 노트 본문이 바뀔 때마다(예: 저장 직후, 또는 사용자가 "다시 계산"을 눌렀을 때)
    /// 다시 계산해서 최신 연관 관계를 보여준다.
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
                let position = previousPositions[note.id] ?? Vector3(
                    x: .random(in: -Physics.spreadRadius...Physics.spreadRadius),
                    y: .random(in: -Physics.spreadRadius...Physics.spreadRadius),
                    z: .random(in: -Physics.spreadRadius...Physics.spreadRadius)
                )
                return Node(id: note.id, title: note.displayTitle, position: position)
            }
            runSimulation()
        } catch {
            // 이 패널은 부가 시각화라, 실패해도 편집 자체를 막지 않고 조용히 비워 둔다.
            edges = []
            nodes = []
        }
    }

    // MARK: - 마우스로 노드 들어올리기/옮기기

    func beginDragging(_ id: UUID) {
        pinnedNodeID = id
    }

    func updateDraggedPosition(_ id: UUID, to position: Vector3) {
        guard let idx = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[idx].position = position
        nodes[idx].velocity = Vector3()
    }

    func endDragging() {
        pinnedNodeID = nil
    }

    // MARK: - 시뮬레이션

    private func runSimulation() {
        simulationTask?.cancel()
        simulationTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.step()
                try? await Task.sleep(nanoseconds: Physics.stepInterval)
            }
        }
    }

    private func step() {
        guard nodes.count > 1 else { return }
        var forces = [UUID: Vector3](minimumCapacity: nodes.count)
        for node in nodes { forces[node.id] = Vector3() }

        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                let a = nodes[i], b = nodes[j]
                let dx = a.position.x - b.position.x
                let dy = a.position.y - b.position.y
                let dz = a.position.z - b.position.z
                let distSq = max(dx * dx + dy * dy + dz * dz, 4)
                let dist = sqrt(distSq)
                let force = Physics.repulsionStrength / distSq
                let fx = (dx / dist) * force, fy = (dy / dist) * force, fz = (dz / dist) * force
                forces[a.id]?.x += fx; forces[a.id]?.y += fy; forces[a.id]?.z += fz
                forces[b.id]?.x -= fx; forces[b.id]?.y -= fy; forces[b.id]?.z -= fz
            }
        }

        let indexByID = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        for edge in edges {
            guard let ai = indexByID[edge.from], let bi = indexByID[edge.to] else { continue }
            let a = nodes[ai], b = nodes[bi]
            let dx = b.position.x - a.position.x
            let dy = b.position.y - a.position.y
            let dz = b.position.z - a.position.z
            let dist = max(sqrt(dx * dx + dy * dy + dz * dz), 0.5)
            let displacement = dist - Physics.springLength
            let force = displacement * Physics.springStrength * edge.weight
            let fx = (dx / dist) * force, fy = (dy / dist) * force, fz = (dz / dist) * force
            forces[a.id]?.x += fx; forces[a.id]?.y += fy; forces[a.id]?.z += fz
            forces[b.id]?.x -= fx; forces[b.id]?.y -= fy; forces[b.id]?.z -= fz
        }

        for i in nodes.indices {
            let id = nodes[i].id
            guard id != pinnedNodeID, let force = forces[id] else { continue }
            var velocity = nodes[i].velocity
            velocity.x = (velocity.x + force.x) * Physics.damping
            velocity.y = (velocity.y + force.y) * Physics.damping
            velocity.z = (velocity.z + force.z) * Physics.damping
            nodes[i].velocity = velocity
            var position = nodes[i].position
            position.x = min(max(position.x + velocity.x, -Physics.boundsRadius), Physics.boundsRadius)
            position.y = min(max(position.y + velocity.y, -Physics.boundsRadius), Physics.boundsRadius)
            position.z = min(max(position.z + velocity.z, -Physics.boundsRadius), Physics.boundsRadius)
            nodes[i].position = position
        }
    }
}
