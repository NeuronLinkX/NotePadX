import AppKit
import PDFKit
import SwiftUI

/// PDFKit의 PDFView를 SwiftUI로 감싼다. VS Code의 내장 뷰어처럼, 파일을 다른 앱으로
/// 넘기지 않고 이 창 안에서 곧바로 훑어볼 수 있게 한다(스펙: Office Viewer — PDF).
struct PDFPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        guard nsView.document?.documentURL != url else { return }
        nsView.document = PDFDocument(url: url)
    }
}

/// 파일 이름·페이지 수와 "Preview 앱으로 열기"/"닫기"를 갖춘 시트. 노트에 첨부된 PDF를
/// 클릭했을 때, 그리고 File > PDF 열기…로 임의의 PDF를 열었을 때 둘 다 이 시트를 쓴다.
struct PDFPreviewSheet: View {
    let url: URL
    let onClose: () -> Void

    private var pageCount: Int? {
        PDFDocument(url: url)?.pageCount
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent).font(.headline).lineLimit(1)
                    if let pageCount {
                        Text("\(pageCount)페이지").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("기본 앱으로 열기") { NSWorkspace.shared.open(url) }
                Button("닫기") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()
            PDFPreviewView(url: url)
        }
        .frame(minWidth: 640, minHeight: 720)
    }
}
