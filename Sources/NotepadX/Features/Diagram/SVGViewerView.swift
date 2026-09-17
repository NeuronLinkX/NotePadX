import AppKit
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import WebKit

/// SVG 뷰어(스펙: 다이어그램 그리기 도구 대신 SVG 불러오기/보기/저장만). 도형을 직접 그리는
/// 기능은 없다 — 이미 있는 .svg 파일을 불러와 보여주고, 필요하면 다른 위치에 다시 저장한다.
struct SVGViewerView: View {
    let svgText: String
    let onImport: (String) -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { importSVG() } label: {
                    Label("SVG 불러오기", systemImage: "square.and.arrow.down")
                }
                Spacer()
                Button { exportSVG() } label: {
                    Label("SVG로 저장", systemImage: "square.and.arrow.up")
                }
                .disabled(svgText.isEmpty)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(8)
            Divider()

            if svgText.isEmpty {
                ContentUnavailableView(
                    "SVG 파일을 불러오세요",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("위의 \"SVG 불러오기\"로 .svg 파일을 열면 여기 보여줘요.")
                )
            } else {
                SVGRenderView(svgText: svgText)
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

    private func importSVG() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.svg]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            onImport(text)
        } catch {
            errorMessage = "SVG를 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func exportSVG() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "다이어그램.svg"
        panel.allowedContentTypes = [.svg]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try svgText.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "SVG로 저장하지 못했습니다: \(error.localizedDescription)"
        }
    }
}

/// SVG를 그대로 렌더링만 한다 — WKWebView가 SVG를 네이티브로 그릴 수 있는 유일하게
/// 간단한 방법이라, 다른 파싱 라이브러리 없이 그대로 맡긴다.
private struct SVGRenderView: NSViewRepresentable {
    let svgText: String

    func makeNSView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let html = """
        <html><body style="margin:0;display:flex;align-items:center;justify-content:center;background:white;">
        \(svgText)
        </body></html>
        """
        nsView.loadHTMLString(html, baseURL: nil)
    }
}
