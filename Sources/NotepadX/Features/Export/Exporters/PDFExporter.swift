import AppKit
@preconcurrency import WebKit

enum PDFExportError: LocalizedError {
    case loadFailed
    var errorDescription: String? { "PDF를 만들기 위한 페이지를 렌더링하지 못했습니다." }
}

/// 완성된 HTML(제목/메타데이터/인쇄용 CSS까지 포함)을 오프스크린 WKWebView에 로드하고
/// WKWebView의 네이티브 PDF 생성 기능으로 내보낸다. 페이지 나눔은 WebKit이 @page 크기에
/// 맞춰 자동으로 처리한다.
@MainActor
enum PDFExporter {
    static func export(html: String, pageSize: CGSize) async throws -> Data {
        let webView = WKWebView(frame: NSRect(origin: .zero, size: pageSize))
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter
        webView.loadHTMLString(html, baseURL: WebEditorResources.webEditorDirectoryURL)

        let loaded = await waiter.waitForLoad()
        guard loaded else { throw PDFExportError.loadFailed }

        let configuration = WKPDFConfiguration()
        return try await webView.pdf(configuration: configuration)
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?

    func waitForLoad() async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(returning: true)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(returning: false)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(returning: false)
        continuation = nil
    }
}
