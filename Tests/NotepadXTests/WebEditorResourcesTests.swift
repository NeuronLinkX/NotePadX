import XCTest
@testable import NotepadX

final class WebEditorResourcesTests: XCTestCase {
    func testIndexHTMLIsBundledAndReadable() throws {
        guard let url = WebEditorResources.indexHTMLURL else {
            return XCTFail("WebEditorResources.indexHTMLURL is nil — Package.swift resources 설정을 확인하세요")
        }
        let html = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(html.contains("editor.css"))
        XCTAssertTrue(html.contains("dist/editor.bundle.js"))
        XCTAssertTrue(html.contains("Content-Security-Policy"))
    }

    func testEditorBundleJSIsPresentAndNonTrivial() throws {
        guard let directory = WebEditorResources.webEditorDirectoryURL else {
            return XCTFail("WebEditorResources.webEditorDirectoryURL is nil")
        }
        let bundleURL = directory.appendingPathComponent("dist/editor.bundle.js")
        let data = try Data(contentsOf: bundleURL)
        // Tiptap + lowlight를 번들링한 실제 산출물이라면 최소 100KB는 넘어야 한다
        // (누락되거나 잘못 커밋된 빈 파일을 잡아내기 위한 방어적 검증).
        XCTAssertGreaterThan(data.count, 100_000)
    }

    func testEditorCSSDoesNotReferenceExternalHost() throws {
        guard let directory = WebEditorResources.webEditorDirectoryURL else {
            return XCTFail("WebEditorResources.webEditorDirectoryURL is nil")
        }
        let css = try String(contentsOf: directory.appendingPathComponent("editor.css"), encoding: .utf8)
        XCTAssertFalse(css.contains("http://"))
        XCTAssertFalse(css.contains("https://"))
    }
}
