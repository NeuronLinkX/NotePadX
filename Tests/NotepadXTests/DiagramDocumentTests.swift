import XCTest
@testable import NotepadX

final class DiagramDocumentTests: XCTestCase {
    private func rect(x: Double, y: Double, w: Double = 100, h: Double = 60) -> DiagramShape {
        DiagramShape(kind: .rectangle, center: DiagramPoint(x: x, y: y), width: w, height: h, fillColorHex: "#FFFFFFFF", strokeColorHex: "#000000FF")
    }

    func testEdgePointPicksRightEdgeWhenOtherShapeIsToTheRight() {
        let shape = rect(x: 100, y: 100)
        let point = DiagramDocument.edgePoint(of: shape, towards: DiagramPoint(x: 500, y: 100))
        XCTAssertEqual(point.x, 150, accuracy: 0.001, "오른쪽에 있는 상대를 향할 땐 우측 변 중점이어야 한다")
        XCTAssertEqual(point.y, 100, accuracy: 0.001)
    }

    func testEdgePointPicksBottomEdgeWhenOtherShapeIsBelow() {
        let shape = rect(x: 100, y: 100)
        let point = DiagramDocument.edgePoint(of: shape, towards: DiagramPoint(x: 100, y: 500))
        XCTAssertEqual(point.x, 100, accuracy: 0.001)
        XCTAssertEqual(point.y, 130, accuracy: 0.001, "아래쪽에 있는 상대를 향할 땐 하단 변 중점이어야 한다")
    }

    func testStraightConnectorPathHasExactlyTwoPoints() {
        var document = DiagramDocument()
        let a = rect(x: 0, y: 0)
        let b = rect(x: 400, y: 0)
        document.shapes = [a, b]
        let connector = DiagramConnector(
            from: DiagramConnectorEndpoint(shapeID: a.id, freePoint: a.center),
            to: DiagramConnectorEndpoint(shapeID: b.id, freePoint: b.center),
            routing: .straight
        )
        let path = document.path(for: connector)
        XCTAssertEqual(path.count, 2)
    }

    /// 스펙: "박스가 멀리 있으면 꺾은 90도 각도의 직선이 가서 꽂게 해주기" — 파워포인트 커넥터처럼
    /// 중간에서 수평→수직으로 한 번 꺾인 4점 경로가 나와야 한다.
    func testOrthogonalConnectorPathBendsOnceAtTheMidpoint() {
        var document = DiagramDocument()
        let a = rect(x: 0, y: 0)
        let b = rect(x: 400, y: 300)
        document.shapes = [a, b]
        let connector = DiagramConnector(
            from: DiagramConnectorEndpoint(shapeID: a.id, freePoint: a.center),
            to: DiagramConnectorEndpoint(shapeID: b.id, freePoint: b.center),
            routing: .orthogonal
        )
        let path = document.path(for: connector)
        XCTAssertEqual(path.count, 4)
        // 중간 두 점이 같은 x(수직 구간)를 공유해야 "한 번 꺾인" 모양이 된다.
        XCTAssertEqual(path[1].x, path[2].x, accuracy: 0.001)
        XCTAssertEqual(path[0].y, path[1].y, accuracy: 0.001)
        XCTAssertEqual(path[2].y, path[3].y, accuracy: 0.001)
    }

    func testFreeEndpointIgnoresShapesAndUsesItsOwnPoint() {
        let document = DiagramDocument()
        let endpoint = DiagramConnectorEndpoint(shapeID: nil, freePoint: DiagramPoint(x: 42, y: 99))
        let resolved = document.resolvedPoint(for: endpoint, towards: DiagramPoint(x: 0, y: 0))
        XCTAssertEqual(resolved, DiagramPoint(x: 42, y: 99))
    }

    func testShapeContainingPointFindsTheRectangleUnderThatPoint() {
        var document = DiagramDocument()
        document.shapes = [rect(x: 100, y: 100), rect(x: 400, y: 100)]
        XCTAssertEqual(document.shape(containing: DiagramPoint(x: 105, y: 110))?.center.x, 100)
        XCTAssertNil(document.shape(containing: DiagramPoint(x: 250, y: 100)), "두 도형 사이 빈 공간은 어떤 도형에도 속하지 않아야 한다")
    }

    func testDerivedPlainTextJoinsNonEmptyShapeText() {
        var document = DiagramDocument()
        document.shapes = [
            DiagramShape(kind: .text, center: .init(x: 0, y: 0), width: 100, height: 30, text: "시작", fillColorHex: "#FFFFFF00", strokeColorHex: "#000000FF"),
            DiagramShape(kind: .rectangle, center: .init(x: 0, y: 0), width: 100, height: 30, text: "", fillColorHex: "#FFFFFFFF", strokeColorHex: "#000000FF"),
            DiagramShape(kind: .text, center: .init(x: 0, y: 0), width: 100, height: 30, text: "끝", fillColorHex: "#FFFFFF00", strokeColorHex: "#000000FF"),
        ]
        XCTAssertEqual(document.derivedPlainText, "시작 끝")
    }
}
