import Foundation

/// SVG 다이어그램 편집기(새 문서 > 다이어그램 만들기)의 저장 형식. 실제 SVG 마크업이
/// 아니라 도형 그래프 자체를 저장해서, 다시 열었을 때도 마우스로 계속 조정할 수 있게
/// 한다 — SVG 파일은 "내보내기" 시점에만 이 모델로부터 만들어진다(DiagramSVGCodec 참고).
struct DiagramPoint: Codable, Sendable, Equatable {
    var x: Double
    var y: Double
}

enum DiagramShapeKind: String, Codable, Sendable {
    case rectangle
    case text
}

struct DiagramShape: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var kind: DiagramShapeKind
    var center: DiagramPoint
    var width: Double
    var height: Double
    var text: String = ""
    var fillColorHex: String
    var strokeColorHex: String
}

/// 화살표 굴절 방식. straight는 두 접점을 곧장 잇고, orthogonal은 파워포인트 커넥터처럼
/// 중간에서 한 번 꺾어(수평→수직→수평) 잇는다.
enum ConnectorRouting: String, Codable, Sendable {
    case straight
    case orthogonal
}

/// 화살표 한쪽 끝. shapeID가 있으면 그 도형 경계를 따라다니고(도형이 움직이면 접점도 같이
/// 움직임), 없으면 freePoint에 고정된 자유 좌표다 — "화살표를 원하는 위치로 직접 조정"을
/// shapeID를 nil로 만드는 것으로 표현한다.
struct DiagramConnectorEndpoint: Codable, Sendable, Equatable {
    var shapeID: UUID?
    var freePoint: DiagramPoint
}

struct DiagramConnector: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var from: DiagramConnectorEndpoint
    var to: DiagramConnectorEndpoint
    var routing: ConnectorRouting = .straight
    var strokeColorHex: String = "#3A3A3C"
}

struct DiagramDocument: Codable, Sendable, Equatable {
    var shapes: [DiagramShape] = []
    var connectors: [DiagramConnector] = []

    /// 검색/미리보기용 순수 텍스트 — 도형에 적힌 글자를 이어 붙인다.
    var derivedPlainText: String {
        shapes.map(\.text).filter { !$0.isEmpty }.joined(separator: " ")
    }

    func shape(_ id: UUID?) -> DiagramShape? {
        guard let id else { return nil }
        return shapes.first { $0.id == id }
    }

    /// 화살표 끝점을 드래그해 도형 위에 놓았을 때 "이 도형에 붙인다"를 판정하는 데 쓴다.
    func shape(containing point: DiagramPoint) -> DiagramShape? {
        shapes.first {
            abs(point.x - $0.center.x) <= $0.width / 2 && abs(point.y - $0.center.y) <= $0.height / 2
        }
    }

    /// 끝점의 실제 렌더링 좌표. 도형에 붙어 있으면 그 도형 경계에서 상대 지점 쪽을 향하는
    /// 변의 중점을, 아니면 자유 좌표를 그대로 돌려준다.
    func resolvedPoint(for endpoint: DiagramConnectorEndpoint, towards other: DiagramPoint) -> DiagramPoint {
        guard let shape = shape(endpoint.shapeID) else { return endpoint.freePoint }
        return Self.edgePoint(of: shape, towards: other)
    }

    /// 도형 경계 4변 중 상대 지점 쪽을 향하는 변의 중점(단순화된 접점 계산 — 도형마다
    /// 접점을 여러 개 두는 대신 상/하/좌/우 중 하나만 골라 파워포인트의 "자동 연결"과
    /// 비슷하게 동작하게 한다).
    static func edgePoint(of shape: DiagramShape, towards other: DiagramPoint) -> DiagramPoint {
        let dx = other.x - shape.center.x
        let dy = other.y - shape.center.y
        let halfW = shape.width / 2
        let halfH = shape.height / 2
        guard dx != 0 || dy != 0 else { return shape.center }
        if abs(dx) * halfH > abs(dy) * halfW {
            return DiagramPoint(x: shape.center.x + (dx > 0 ? halfW : -halfW), y: shape.center.y)
        } else {
            return DiagramPoint(x: shape.center.x, y: shape.center.y + (dy > 0 ? halfH : -halfH))
        }
    }

    /// 커넥터를 실제로 그릴 점들의 나열. straight면 [시작, 끝], orthogonal이면 중간에서
    /// 한 번 꺾인 [시작, 중간1, 중간2, 끝] 4점이다.
    func path(for connector: DiagramConnector) -> [DiagramPoint] {
        let toRef = shape(connector.to.shapeID)?.center ?? connector.to.freePoint
        let fromRef = shape(connector.from.shapeID)?.center ?? connector.from.freePoint
        let start = resolvedPoint(for: connector.from, towards: toRef)
        let end = resolvedPoint(for: connector.to, towards: fromRef)
        switch connector.routing {
        case .straight:
            return [start, end]
        case .orthogonal:
            let midX = (start.x + end.x) / 2
            return [start, DiagramPoint(x: midX, y: start.y), DiagramPoint(x: midX, y: end.y), end]
        }
    }
}
