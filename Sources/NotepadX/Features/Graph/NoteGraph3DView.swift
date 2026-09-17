import AppKit
import SceneKit
import SwiftUI

/// "연관 메모" 그래프를 3D로 그린다(스펙: 신경망 이미지처럼 3D로 애니메이팅되고, 마우스로
/// 노드를 들어 올릴 수 있게). 하얀 배경에 검은 선으로 대비를 뚜렷하게 하고, 평소에는
/// 라벨을 작게만 보여주다가 마우스를 올리면 그 노드의 글자만 커지게 한다(작은 글씨가
/// 다닥다닥 겹쳐 안 보이는 문제를 이렇게 푼다). 카메라는 두 손가락 드래그/스크롤로
/// 자유롭게 궤도 회전·확대(allowsCameraControl)할 수 있고, 노드를 클릭한 채 드래그하면
/// 카메라를 바라보는 평면을 따라 그 노드만 옮길 수 있다.
struct NoteGraph3DView: NSViewRepresentable {
    @ObservedObject var viewModel: NoteGraphViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> InteractiveSCNView {
        let view = InteractiveSCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.cameraNode
        view.allowsCameraControl = true
        view.backgroundColor = .white
        view.antialiasingMode = .multisampling4X
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: InteractiveSCNView, context: Context) {
        context.coordinator.sync(nodes: viewModel.nodes, edges: viewModel.edges)
    }

    @MainActor
    final class Coordinator {
        let scene = SCNScene()
        let cameraNode = SCNNode()
        weak var viewModel: NoteGraphViewModel?

        private var nodeSpheres: [UUID: SCNNode] = [:]
        private var edgeCylinders: [String: SCNNode] = [:]
        private var hoveredNodeID: UUID?

        private static let normalTextScale: Float = 0.5
        private static let hoveredTextScale: Float = 1.6

        init(viewModel: NoteGraphViewModel) {
            self.viewModel = viewModel
            setupCamera()
            setupLighting()
        }

        private func setupCamera() {
            let camera = SCNCamera()
            camera.fieldOfView = 55
            camera.zFar = 400
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 0, 130)
            scene.rootNode.addChildNode(cameraNode)
        }

        private func setupLighting() {
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.color = NSColor(white: 0.7, alpha: 1)
            scene.rootNode.addChildNode(ambient)

            let directional = SCNNode()
            directional.light = SCNLight()
            directional.light?.type = .directional
            directional.light?.color = NSColor(white: 0.9, alpha: 1)
            directional.position = SCNVector3(40, 50, 70)
            directional.look(at: SCNVector3Zero)
            scene.rootNode.addChildNode(directional)
        }

        /// 매번 SwiftUI가 뷰를 갱신할 때(= 물리 시뮬레이션이 한 스텝 진행할 때마다) 불린다.
        /// 지금 사용자가 드래그 중인 노드는 애니메이션 없이 즉시 마우스를 따라가야 하고,
        /// 나머지는 SceneKit의 암시적 애니메이션으로 부드럽게 스텝 사이를 보간하게 둔다.
        func sync(nodes: [NoteGraphViewModel.Node], edges: [NoteSimilarityEngine.Edge]) {
            let pinnedID = viewModel?.pinnedNodeID
            var seenNodeIDs = Set<UUID>()
            for node in nodes {
                seenNodeIDs.insert(node.id)
                let scnNode = nodeSpheres[node.id] ?? makeNodeSphere(for: node)
                let newPosition = SCNVector3(Float(node.position.x), Float(node.position.y), Float(node.position.z))
                SCNTransaction.begin()
                SCNTransaction.animationDuration = node.id == pinnedID ? 0 : 0.2
                scnNode.position = newPosition
                SCNTransaction.commit()
                nodeSpheres[node.id] = scnNode
            }
            for (id, scnNode) in nodeSpheres where !seenNodeIDs.contains(id) {
                scnNode.removeFromParentNode()
                nodeSpheres.removeValue(forKey: id)
            }

            var seenEdgeIDs = Set<String>()
            let positionByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })
            for edge in edges {
                guard let from = positionByID[edge.from], let to = positionByID[edge.to] else { continue }
                seenEdgeIDs.insert(edge.id)
                let cylinder = edgeCylinders[edge.id] ?? makeEdgeCylinder(weight: edge.weight)
                positionCylinder(
                    cylinder,
                    from: SCNVector3(Float(from.x), Float(from.y), Float(from.z)),
                    to: SCNVector3(Float(to.x), Float(to.y), Float(to.z))
                )
                edgeCylinders[edge.id] = cylinder
            }
            for (id, cylinder) in edgeCylinders where !seenEdgeIDs.contains(id) {
                cylinder.removeFromParentNode()
                edgeCylinders.removeValue(forKey: id)
            }
        }

        /// 노드 위에 마우스를 올리면 그 노드의 글자만 크게 키운다 — 항상 다 크게 두면
        /// 촘촘한 그래프에서 라벨끼리 겹쳐 아무것도 못 읽는다.
        func setHoveredNode(_ id: UUID?) {
            guard hoveredNodeID != id else { return }
            if let previous = hoveredNodeID, let node = nodeSpheres[previous] {
                setLabelEmphasis(on: node, emphasized: false)
            }
            hoveredNodeID = id
            if let id, let node = nodeSpheres[id] {
                setLabelEmphasis(on: node, emphasized: true)
            }
        }

        /// 마우스를 올린 노드는 글자를 굵게 보이도록 SCNText 자체를 살짝 눌러 만든(extrusion
        /// 없이 폰트만 bold로) 텍스트로 다시 만들고, 진한 보라색으로 강조한다.
        private func setLabelEmphasis(on sphereNode: SCNNode, emphasized: Bool) {
            guard let textNode = sphereNode.childNodes.first, let text = textNode.geometry as? SCNText else { return }
            let scale = emphasized ? Self.hoveredTextScale : Self.normalTextScale
            text.font = emphasized ? .boldSystemFont(ofSize: 3.6) : .systemFont(ofSize: 3.6)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.12
            textNode.scale = SCNVector3(scale, scale, scale)
            textNode.renderingOrder = emphasized ? 10 : 0
            text.firstMaterial?.diffuse.contents = emphasized ? Self.hoverLabelColor : NSColor.black
            SCNTransaction.commit()
        }

        /// 예쁜 진보라색 — 시스템 purple보다 채도를 조금 낮춰 흰 배경에서 튀지 않으면서도 또렷하다.
        private static let hoverLabelColor = NSColor(calibratedRed: 0.55, green: 0.24, blue: 0.82, alpha: 1)

        private func makeNodeSphere(for node: NoteGraphViewModel.Node) -> SCNNode {
            let sphere = SCNSphere(radius: 3.4)
            sphere.firstMaterial?.diffuse.contents = NSColor.controlAccentColor
            sphere.firstMaterial?.emission.contents = NSColor.controlAccentColor.withAlphaComponent(0.4)
            sphere.firstMaterial?.lightingModel = .physicallyBased
            sphere.firstMaterial?.metalness.contents = 0.2
            sphere.firstMaterial?.roughness.contents = 0.4
            let scnNode = SCNNode(geometry: sphere)
            scnNode.name = node.id.uuidString

            let text = SCNText(string: node.title, extrusionDepth: 0)
            text.font = .systemFont(ofSize: 3.6)
            text.flatness = 0.3
            // 배경이 항상 흰색으로 고정이라, 시스템 다크 모드에서도 절대 안 보이는 일이
            // 없게 라벨은 시맨틱 색(labelColor) 대신 실제 검은색을 그대로 쓴다.
            text.firstMaterial?.diffuse.contents = NSColor.black
            text.firstMaterial?.lightingModel = .constant
            let (minBound, maxBound) = text.boundingBox
            let textNode = SCNNode(geometry: text)
            textNode.scale = SCNVector3(Coordinator.normalTextScale, Coordinator.normalTextScale, Coordinator.normalTextScale)
            textNode.position = SCNVector3(-(maxBound.x - minBound.x) * 0.25, 4.6, 0)
            textNode.constraints = [SCNBillboardConstraint()]
            scnNode.addChildNode(textNode)

            scene.rootNode.addChildNode(scnNode)
            return scnNode
        }

        private func makeEdgeCylinder(weight: Double) -> SCNNode {
            let cylinder = SCNCylinder(radius: 0.12 + weight * 0.3, height: 1)
            cylinder.radialSegmentCount = 8
            // 하얀 배경에서 또렷이 보이도록 검은 선으로 — 옅은 파란 반투명 선은 배경/선
            // 대비가 약해 잘 안 보인다는 피드백에 따른 조정이다.
            cylinder.firstMaterial?.diffuse.contents = NSColor.black.withAlphaComponent(0.45 + weight * 0.5)
            cylinder.firstMaterial?.lightingModel = .constant
            let node = SCNNode(geometry: cylinder)
            scene.rootNode.addChildNode(node)
            return node
        }

        /// 원기둥은 기본적으로 자신의 로컬 Y축을 따라 서 있으므로, 두 점을 잇도록
        /// 길이를 다시 맞추고 로컬 Y축이 목표 방향을 향하게 회전시킨다.
        private func positionCylinder(_ node: SCNNode, from: SCNVector3, to: SCNVector3) {
            let dx = to.x - from.x, dy = to.y - from.y, dz = to.z - from.z
            let length = CGFloat(sqrt(dx * dx + dy * dy + dz * dz))
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.2
            (node.geometry as? SCNCylinder)?.height = max(length, 0.001)
            node.position = SCNVector3((from.x + to.x) / 2, (from.y + to.y) / 2, (from.z + to.z) / 2)
            node.look(at: to, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
            SCNTransaction.commit()
        }
    }
}

/// 마우스 클릭+드래그로 노드를 하나 집어 카메라를 바라보는 평면 위에서 옮기고, 마우스를
/// 올리기만 해도(mouseMoved) 그 노드의 라벨이 커지게 한다. allowsCameraControl이 처리하는
/// 궤도 회전(빈 공간 드래그)과 공존하도록, 실제로 구를 맞혔을 때만 드래그 이벤트를
/// 가로채고 그 외에는 그대로 SCNView 기본 처리에 맡긴다.
final class InteractiveSCNView: SCNView {
    weak var coordinator: NoteGraph3DView.Coordinator?
    private var draggedNodeID: UUID?
    private var dragAnchorWorldPosition = SCNVector3Zero
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let hits = hitTest(location, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
        coordinator?.setHoveredNode(hits.first.flatMap { nodeID(for: $0.node) })
        super.mouseMoved(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let hits = hitTest(location, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
        if let hit = hits.first, let id = nodeID(for: hit.node) {
            draggedNodeID = id
            dragAnchorWorldPosition = hit.node.presentation.position
            coordinator?.viewModel?.beginDragging(id)
        } else {
            draggedNodeID = nil
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let id = draggedNodeID else {
            super.mouseDragged(with: event)
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        // 노드가 지금 있는 깊이(카메라 기준 z)를 그대로 유지한 채, 새 화면 좌표를 그
        // 깊이의 3D 평면으로 되돌려서 "카메라를 보는 평면 위에서 미는" 느낌을 만든다.
        let projectedDepth = Float(projectPoint(dragAnchorWorldPosition).z)
        let world = unprojectPoint(SCNVector3(Float(location.x), Float(location.y), projectedDepth))
        coordinator?.viewModel?.updateDraggedPosition(id, to: .init(x: Double(world.x), y: Double(world.y), z: Double(world.z)))
    }

    override func mouseUp(with event: NSEvent) {
        if draggedNodeID != nil {
            coordinator?.viewModel?.endDragging()
        }
        draggedNodeID = nil
        super.mouseUp(with: event)
    }

    private func nodeID(for node: SCNNode) -> UUID? {
        if let name = node.name, let id = UUID(uuidString: name) { return id }
        if let parentName = node.parent?.name, let id = UUID(uuidString: parentName) { return id }
        return nil
    }
}
