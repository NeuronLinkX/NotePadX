import XCTest
@testable import NotepadX

final class DiagramSVGCodecTests: XCTestCase {
    private func sampleDocument() -> DiagramDocument {
        var document = DiagramDocument()
        let a = DiagramShape(kind: .rectangle, center: .init(x: 100, y: 100), width: 120, height: 60, text: "시작", fillColorHex: "#FFFFFFFF", strokeColorHex: "#3A3A3CFF")
        let b = DiagramShape(kind: .rectangle, center: .init(x: 400, y: 300), width: 120, height: 60, text: "끝", fillColorHex: "#FFFFFFFF", strokeColorHex: "#3A3A3CFF")
        document.shapes = [a, b]
        document.connectors = [
            DiagramConnector(
                from: DiagramConnectorEndpoint(shapeID: a.id, freePoint: a.center),
                to: DiagramConnectorEndpoint(shapeID: b.id, freePoint: b.center),
                routing: .orthogonal
            )
        ]
        return document
    }

    func testExportProducesValidLookingSVGMarkup() {
        let svg = DiagramSVGCodec.export(sampleDocument())
        XCTAssertTrue(svg.hasPrefix("<svg"))
        XCTAssertTrue(svg.contains("</svg>"))
        XCTAssertTrue(svg.contains("<rect"), "사각형 도형이 <rect>로 그려져야 한다")
        XCTAssertTrue(svg.contains("<polyline"), "커넥터가 <polyline>으로 그려져야 한다")
        XCTAssertTrue(svg.contains("시작"))
        XCTAssertTrue(svg.contains("끝"))
    }

    func testExportEscapesShapeTextForXMLSafety() {
        var document = DiagramDocument()
        document.shapes = [DiagramShape(kind: .text, center: .init(x: 0, y: 0), width: 100, height: 30, text: "A < B & C", fillColorHex: "#FFFFFF00", strokeColorHex: "#000000FF")]
        let svg = DiagramSVGCodec.export(document)
        XCTAssertFalse(svg.contains("A < B & C"), "이스케이프되지 않은 원문이 그대로 들어가면 안 된다")
        XCTAssertTrue(svg.contains("A &lt; B &amp; C"))
    }

    func testImportRoundTripsAnExportedDocumentExactly() {
        let original = sampleDocument()
        let svg = DiagramSVGCodec.export(original)
        let imported = DiagramSVGCodec.importDocument(fromSVG: svg)
        XCTAssertEqual(imported, original, "이 도구가 만든 SVG는 도형 그래프를 손실 없이 복원해야 한다")
    }

    func testImportReturnsNilForSVGWithoutEmbeddedMetadata() {
        let plainSVG = "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"10\" height=\"10\"/></svg>"
        XCTAssertNil(DiagramSVGCodec.importDocument(fromSVG: plainSVG), "다른 도구가 만든 일반 SVG는 가져오기 대상이 아니어야 한다")
    }
}
