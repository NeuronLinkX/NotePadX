import SwiftUI
import WebKit

/// RichEditorController가 소유한 WKWebView를 SwiftUI 트리에 얹기만 하는 얇은 래퍼.
/// 문서 로딩/커맨드 전달/브리지 델리게이트는 모두 컨트롤러(및 그 델리게이트인
/// EditorViewModel) 책임이라 이 뷰 자체는 상태를 갖지 않는다.
struct RichEditorWebView: NSViewRepresentable {
    let controller: RichEditorController

    func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
