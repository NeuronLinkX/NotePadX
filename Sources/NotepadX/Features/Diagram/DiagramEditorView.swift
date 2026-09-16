import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// SVG 다이어그램 편집기(스펙: 새 문서 > 다이어그램 만들기). 도형·화살표를 마우스로 직접
/// 배치·조정하고, 이 도구가 만든 형식의 SVG로 내보내거나 다시 불러올 수 있다.
struct DiagramEditorView: View {
    @Binding var document: DiagramDocument

    enum Selection: Equatable {
        case shape(UUID)
        case connector(UUID)
    }

    @State private var selection: Selection?
    @State private var isConnectMode = false
    @State private var connectSourceID: UUID?
    @State private var errorMessage: String?

    private static let canvasSize = CGSize(width: 2200, height: 1500)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let hint = hintMessage {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                Divider()
            }
            ScrollView([.horizontal, .vertical]) {
                canvas
                    .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
                    .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .alert("오류", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var hintMessage: String? {
        guard isConnectMode else { return nil }
        return connectSourceID == nil
            ? "연결을 시작할 도형을 클릭하세요."
            : "연결을 끝낼 도형을 클릭하세요 (Esc 또는 다시 눌러 취소)."
    }

    @ViewBuilder
    private var canvas: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { selection = nil }

            ForEach(document.connectors) { connector in
                ConnectorNodeView(
                    connector: connector,
                    document: document,
                    isSelected: selection == .connector(connector.id),
                    onSelect: { selection = .connector(connector.id) },
                    onUpdateEndpoint: { isStart, endpoint in
                        updateConnectorEndpoint(connector.id, isStart: isStart, endpoint: endpoint)
                    }
                )
            }

            ForEach(document.shapes) { shape in
                ShapeNodeView(
                    shape: shape,
                    isSelected: selection == .shape(shape.id),
                    onSelect: { handleShapeTap(shape.id) },
                    onMove: { moveShape(shape.id, to: $0) },
                    onResize: { resizeShape(shape.id, width: $0, height: $1) }
                )
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { addShape(.rectangle) } label: { Label("사각형", systemImage: "rectangle") }
            Button { addShape(.text) } label: { Label("텍스트", systemImage: "textformat") }
            Button {
                isConnectMode.toggle()
                connectSourceID = nil
            } label: {
                Label("화살표 연결", systemImage: "arrow.up.right")
            }
            .tint(isConnectMode ? Color.accentColor : nil)

            Divider().frame(height: 20)

            selectionInspector

            if selection != nil {
                Button(role: .destructive) { deleteSelection() } label: { Label("삭제", systemImage: "trash") }
            }

            Spacer()

            Button { exportSVG() } label: { Label("SVG로 내보내기", systemImage: "square.and.arrow.up") }
            Button { importSVG() } label: { Label("SVG 불러오기", systemImage: "square.and.arrow.down") }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(8)
    }

    @ViewBuilder
    private var selectionInspector: some View {
        if case .shape(let id) = selection, let shape = document.shapes.first(where: { $0.id == id }) {
            TextField("도형 텍스트", text: Binding(
                get: { shape.text },
                set: { updateShapeText(id, text: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 140)

            if shape.kind == .rectangle {
                ColorPicker("채우기", selection: Binding(
                    get: { Color(hex: shape.fillColorHex) ?? .white },
                    set: { updateShapeFill(id, color: $0) }
                ))
                .labelsHidden()
            }
            ColorPicker("선/글자색", selection: Binding(
                get: { Color(hex: shape.strokeColorHex) ?? .black },
                set: { updateShapeStroke(id, color: $0) }
            ))
            .labelsHidden()
        }

        if case .connector(let id) = selection, let connector = document.connectors.first(where: { $0.id == id }) {
            Picker("", selection: Binding(
                get: { connector.routing },
                set: { updateConnectorRouting(id, routing: $0) }
            )) {
                Text("직선").tag(ConnectorRouting.straight)
                Text("꺾은선").tag(ConnectorRouting.orthogonal)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)

            ColorPicker("선", selection: Binding(
                get: { Color(hex: connector.strokeColorHex) ?? .black },
                set: { updateConnectorColor(id, color: $0) }
            ))
            .labelsHidden()
        }
    }

    // MARK: - 도형/커넥터 편집

    private func addShape(_ kind: DiagramShapeKind) {
        let offset = Double(document.shapes.count % 8) * 24
        let shape = DiagramShape(
            kind: kind,
            center: DiagramPoint(x: 180 + offset, y: 160 + offset),
            width: kind == .text ? 120 : 150,
            height: kind == .text ? 30 : 84,
            text: kind == .text ? "텍스트" : "",
            fillColorHex: "#FFFFFFFF",
            strokeColorHex: "#3A3A3CFF"
        )
        document.shapes.append(shape)
        selection = .shape(shape.id)
    }

    private func handleShapeTap(_ id: UUID) {
        guard isConnectMode else {
            selection = .shape(id)
            return
        }
        if let sourceID = connectSourceID {
            if sourceID != id {
                let sourceCenter = document.shape(sourceID)?.center ?? DiagramPoint(x: 0, y: 0)
                let targetCenter = document.shape(id)?.center ?? DiagramPoint(x: 0, y: 0)
                let connector = DiagramConnector(
                    from: DiagramConnectorEndpoint(shapeID: sourceID, freePoint: sourceCenter),
                    to: DiagramConnectorEndpoint(shapeID: id, freePoint: targetCenter)
                )
                document.connectors.append(connector)
                selection = .connector(connector.id)
            }
            connectSourceID = nil
            isConnectMode = false
        } else {
            connectSourceID = id
        }
    }

    private func moveShape(_ id: UUID, to center: DiagramPoint) {
        guard let idx = document.shapes.firstIndex(where: { $0.id == id }) else { return }
        document.shapes[idx].center = center
    }

    private func resizeShape(_ id: UUID, width: Double, height: Double) {
        guard let idx = document.shapes.firstIndex(where: { $0.id == id }) else { return }
        document.shapes[idx].width = width
        document.shapes[idx].height = height
    }

    private func updateShapeText(_ id: UUID, text: String) {
        guard let idx = document.shapes.firstIndex(where: { $0.id == id }) else { return }
        document.shapes[idx].text = text
    }

    private func updateShapeFill(_ id: UUID, color: Color) {
        guard let idx = document.shapes.firstIndex(where: { $0.id == id }) else { return }
        document.shapes[idx].fillColorHex = color.hexStringWithAlpha
    }

    private func updateShapeStroke(_ id: UUID, color: Color) {
        guard let idx = document.shapes.firstIndex(where: { $0.id == id }) else { return }
        document.shapes[idx].strokeColorHex = color.hexStringWithAlpha
    }

    private func updateConnectorEndpoint(_ id: UUID, isStart: Bool, endpoint: DiagramConnectorEndpoint) {
        guard let idx = document.connectors.firstIndex(where: { $0.id == id }) else { return }
        if isStart {
            document.connectors[idx].from = endpoint
        } else {
            document.connectors[idx].to = endpoint
        }
    }

    private func updateConnectorRouting(_ id: UUID, routing: ConnectorRouting) {
        guard let idx = document.connectors.firstIndex(where: { $0.id == id }) else { return }
        document.connectors[idx].routing = routing
    }

    private func updateConnectorColor(_ id: UUID, color: Color) {
        guard let idx = document.connectors.firstIndex(where: { $0.id == id }) else { return }
        document.connectors[idx].strokeColorHex = color.hexStringWithAlpha
    }

    private func deleteSelection() {
        switch selection {
        case .shape(let id):
            document.shapes.removeAll { $0.id == id }
            document.connectors.removeAll { $0.from.shapeID == id || $0.to.shapeID == id }
        case .connector(let id):
            document.connectors.removeAll { $0.id == id }
        case nil:
            break
        }
        selection = nil
    }

    // MARK: - SVG 내보내기/불러오기

    private func exportSVG() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "다이어그램.svg"
        panel.allowedContentTypes = [.svg]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DiagramSVGCodec.export(document).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "SVG로 내보내지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func importSVG() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.svg]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let svg = try String(contentsOf: url, encoding: .utf8)
            guard let imported = DiagramSVGCodec.importDocument(fromSVG: svg) else {
                errorMessage = "이 편집기에서 만든 SVG만 다시 불러와 고칠 수 있습니다. 이 파일에는 편집 정보가 없어요."
                return
            }
            document = imported
            selection = nil
        } catch {
            errorMessage = "SVG를 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }
}

// MARK: - 도형 노드

private struct ShapeNodeView: View {
    let shape: DiagramShape
    let isSelected: Bool
    let onSelect: () -> Void
    let onMove: (DiagramPoint) -> Void
    let onResize: (Double, Double) -> Void

    @State private var dragStartCenter: DiagramPoint?
    @State private var dragStartSize: (width: Double, height: Double)?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            content
                .frame(width: shape.width, height: shape.height)
                .contentShape(Rectangle())
                .onTapGesture { onSelect() }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if dragStartCenter == nil { dragStartCenter = shape.center }
                            let start = dragStartCenter ?? shape.center
                            onMove(DiagramPoint(x: start.x + value.translation.width, y: start.y + value.translation.height))
                        }
                        .onEnded { _ in dragStartCenter = nil }
                )

            if isSelected {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 12)
                    .offset(x: 6, y: 6)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if dragStartSize == nil { dragStartSize = (shape.width, shape.height) }
                                let start = dragStartSize ?? (shape.width, shape.height)
                                onResize(max(40, start.width + value.translation.width), max(24, start.height + value.translation.height))
                            }
                            .onEnded { _ in dragStartSize = nil }
                    )
            }
        }
        .position(x: shape.center.x, y: shape.center.y)
    }

    @ViewBuilder
    private var content: some View {
        switch shape.kind {
        case .rectangle:
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: shape.fillColorHex) ?? .white)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: shape.strokeColorHex) ?? .black, lineWidth: isSelected ? 3 : 1.5)
                )
                .overlay(shapeLabel)
        case .text:
            (isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                .overlay(shapeLabel)
        }
    }

    private var shapeLabel: some View {
        Text(shape.text)
            .font(.system(size: 13))
            .foregroundStyle(Color(hex: shape.strokeColorHex) ?? .primary)
            .multilineTextAlignment(.center)
            .padding(4)
            .allowsHitTesting(false)
    }
}

// MARK: - 커넥터(화살표) 노드

private struct ConnectorNodeView: View {
    let connector: DiagramConnector
    let document: DiagramDocument
    let isSelected: Bool
    let onSelect: () -> Void
    let onUpdateEndpoint: (_ isStart: Bool, _ endpoint: DiagramConnectorEndpoint) -> Void

    var body: some View {
        let points = document.path(for: connector)
        ZStack {
            linePath(points)
                .stroke(Color(hex: connector.strokeColorHex) ?? .black, lineWidth: isSelected ? 3 : 2)
            if points.count >= 2 {
                arrowhead(from: points[points.count - 2], to: points[points.count - 1])
                    .fill(Color(hex: connector.strokeColorHex) ?? .black)
            }
            // 넓은 투명 히트 영역 — 가는 선을 정확히 클릭하기 어려운 문제를 완화한다.
            linePath(points)
                .stroke(Color.white.opacity(0.001), lineWidth: 16)
                .onTapGesture { onSelect() }

            if let start = points.first {
                endpointHandle(at: start, isStart: true)
            }
            if let end = points.last {
                endpointHandle(at: end, isStart: false)
            }
        }
    }

    private func linePath(_ points: [DiagramPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: CGPoint(x: first.x, y: first.y))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x, y: point.y))
            }
        }
    }

    private func arrowhead(from: DiagramPoint, to: DiagramPoint, size: Double = 9) -> Path {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let p1 = CGPoint(x: to.x - size * cos(angle - .pi / 7), y: to.y - size * sin(angle - .pi / 7))
        let p2 = CGPoint(x: to.x - size * cos(angle + .pi / 7), y: to.y - size * sin(angle + .pi / 7))
        var path = Path()
        path.move(to: CGPoint(x: to.x, y: to.y))
        path.addLine(to: p1)
        path.addLine(to: p2)
        path.closeSubpath()
        return path
    }

    @State private var dragStartPoint: DiagramPoint?

    private func endpointHandle(at point: DiagramPoint, isStart: Bool) -> some View {
        Circle()
            .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.001))
            .frame(width: 12, height: 12)
            .position(x: point.x, y: point.y)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStartPoint == nil { dragStartPoint = point }
                        let start = dragStartPoint ?? point
                        let newPoint = DiagramPoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
                        let attachedShapeID = document.shape(containing: newPoint)?.id
                        onUpdateEndpoint(isStart, DiagramConnectorEndpoint(shapeID: attachedShapeID, freePoint: newPoint))
                    }
                    .onEnded { _ in dragStartPoint = nil }
            )
            .onTapGesture { onSelect() }
    }
}
