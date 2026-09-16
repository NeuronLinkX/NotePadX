import Foundation

/// DiagramDocument ↔ SVG 파일 변환 (스펙: 다이어그램을 SVG로 저장).
///
/// 도형은 실제 SVG 마크업(rect/polyline/text)으로 그려서 다른 프로그램(브라우저, Preview 등)
/// 에서도 그대로 열어볼 수 있게 하고, 이 편집기가 다시 열어 계속 고칠 수 있도록 원본 도형
/// 그래프를 `<metadata>` 태그에 JSON(base64)으로 함께 묻어 둔다.
///
/// 이 태그가 없는(다른 도구가 만든) 임의의 SVG는 가져오기 대상이 아니다 — 변형·그룹·곡선 등
/// 표현이 무한히 다양한 일반 SVG를 도형 그래프로 역파싱하는 것은 이 도구의 목표가 아니며,
/// 시도한다면 원본과 다르게 깨진 결과를 만들어 오히려 신뢰를 해친다.
enum DiagramSVGCodec {
    private static let metadataOpenTag = "<metadata id=\"notepadx-diagram-v1\">"
    private static let metadataCloseTag = "</metadata>"

    static func export(_ document: DiagramDocument) -> String {
        let bounds = contentBounds(document)
        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(bounds.width))" height="\(Int(bounds.height))" viewBox="\(Int(bounds.minX)) \(Int(bounds.minY)) \(Int(bounds.width)) \(Int(bounds.height))">
        <defs>
        <marker id="arrowhead" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
        <path d="M 0 0 L 10 5 L 0 10 z" fill="context-stroke"/>
        </marker>
        </defs>
        <rect x="\(Int(bounds.minX))" y="\(Int(bounds.minY))" width="\(Int(bounds.width))" height="\(Int(bounds.height))" fill="white"/>\n
        """

        for connector in document.connectors {
            let points = document.path(for: connector).map { "\($0.x),\($0.y)" }.joined(separator: " ")
            svg += "<polyline points=\"\(points)\" fill=\"none\" stroke=\"\(rgbHex(connector.strokeColorHex))\" stroke-width=\"2\" marker-end=\"url(#arrowhead)\"/>\n"
        }

        for shape in document.shapes {
            let stroke = rgbHex(shape.strokeColorHex)
            if shape.kind == .rectangle {
                let x = shape.center.x - shape.width / 2
                let y = shape.center.y - shape.height / 2
                svg += "<rect x=\"\(x)\" y=\"\(y)\" width=\"\(shape.width)\" height=\"\(shape.height)\" rx=\"6\" fill=\"\(rgbHex(shape.fillColorHex))\" stroke=\"\(stroke)\" stroke-width=\"1.5\"/>\n"
            }
            if !shape.text.isEmpty {
                svg += "<text x=\"\(shape.center.x)\" y=\"\(shape.center.y)\" text-anchor=\"middle\" dominant-baseline=\"middle\" fill=\"\(stroke)\" font-size=\"13\" font-family=\"-apple-system, sans-serif\">\(HTMLEscape.escape(shape.text))</text>\n"
            }
        }

        if let data = try? JSONEncoder().encode(document) {
            svg += "\(metadataOpenTag)\(data.base64EncodedString())\(metadataCloseTag)\n"
        }

        svg += "</svg>\n"
        return svg
    }

    /// 이 도구가 만든 SVG(metadata 포함)에서만 편집 가능한 도형 그래프를 복원한다.
    static func importDocument(fromSVG svg: String) -> DiagramDocument? {
        guard let openRange = svg.range(of: metadataOpenTag),
              let closeRange = svg.range(of: metadataCloseTag, range: openRange.upperBound..<svg.endIndex) else {
            return nil
        }
        let base64 = svg[openRange.upperBound..<closeRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(DiagramDocument.self, from: data)
    }

    /// "#rrggbbaa" 저장 형식에서 SVG의 fill/stroke 속성이 받는 "#rrggbb"만 남긴다.
    private static func rgbHex(_ hexWithAlpha: String) -> String {
        var value = hexWithAlpha
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 8 else { return "#" + value }
        return "#" + value.prefix(6)
    }

    private static func contentBounds(_ document: DiagramDocument) -> (minX: Double, minY: Double, width: Double, height: Double) {
        var minX = 0.0, minY = 0.0, maxX = 800.0, maxY = 600.0
        for shape in document.shapes {
            minX = min(minX, shape.center.x - shape.width / 2 - 40)
            minY = min(minY, shape.center.y - shape.height / 2 - 40)
            maxX = max(maxX, shape.center.x + shape.width / 2 + 40)
            maxY = max(maxY, shape.center.y + shape.height / 2 + 40)
        }
        for connector in document.connectors {
            for point in document.path(for: connector) {
                minX = min(minX, point.x - 20)
                minY = min(minY, point.y - 20)
                maxX = max(maxX, point.x + 20)
                maxY = max(maxY, point.y + 20)
            }
        }
        return (minX, minY, maxX - minX, maxY - minY)
    }
}
