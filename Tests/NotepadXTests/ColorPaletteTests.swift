import SwiftUI
import XCTest
@testable import NotepadX

final class ColorPaletteTests: XCTestCase {
    func testNormalizesHexAndRGBForms() {
        XCTAssertEqual(ColorPalettes.normalizedHex(from: "#dc2626"), "#DC2626")
        XCTAssertEqual(ColorPalettes.normalizedHex(from: "#fa0"), "#FFAA00")
        XCTAssertEqual(ColorPalettes.normalizedHex(from: "rgb(220, 38, 38)"), "#DC2626")
        XCTAssertEqual(ColorPalettes.normalizedHex(from: "rgba(0, 0, 0, 0.5)"), "#000000")
    }

    func testRejectsMissingOrUnsupportedValues() {
        XCTAssertNil(ColorPalettes.normalizedHex(from: nil))
        XCTAssertNil(ColorPalettes.normalizedHex(from: ""))
        XCTAssertNil(ColorPalettes.normalizedHex(from: "red"))
        XCTAssertNil(ColorPalettes.normalizedHex(from: "#12345"))
    }

    func testPaletteSwatchesAreValidAndUnique() {
        for palette in [ColorPalettes.text, ColorPalettes.highlight] {
            XCTAssertEqual(Set(palette.map(\.hex)).count, palette.count, "같은 색이 두 번 들어 있으면 선택 표시가 겹친다")
            for swatch in palette {
                XCTAssertNotNil(Color(hex: swatch.hex), "\(swatch.name) 색이 파싱되지 않음")
            }
        }
    }

    func testFontFamilyLabelShowsOnlyTheFirstFamilyFromACSSStack() {
        XCTAssertEqual(EditorToolbar.displayName(forFontFamily: "\"Pretendard Variable\", Pretendard, -apple-system, sans-serif"), "Pretendard Variable")
        XCTAssertEqual(EditorToolbar.displayName(forFontFamily: "Menlo"), "Menlo")
        XCTAssertEqual(EditorToolbar.displayName(forFontFamily: nil), "글꼴")
        XCTAssertEqual(EditorToolbar.displayName(forFontFamily: ""), "글꼴")
    }
}
