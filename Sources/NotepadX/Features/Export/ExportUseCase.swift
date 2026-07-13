import Foundation

enum ExportOutput {
    case data(Data)
    case fileWrapper(FileWrapper)
}

/// 형식별 변환기(Exporters/*)를 하나의 진입점으로 모은다. HTML/PDF/RTF는 실제 편집기
/// 렌더러(WKWebView)를 한 번 더 띄워야 해서 MainActor로 묶는다.
@MainActor
struct ExportUseCase {
    func export(note: Note, title: String, document: EditorDocument, format: ExportFormat, options: ExportOptions) async throws -> ExportOutput {
        switch format {
        case .plainText:
            let text = PlainTextExporter.export(title: title, plainText: document.derivedPlainText, note: note, options: options)
            return .data(Data(text.utf8))

        case .markdown:
            let text = MarkdownExporter.export(title: title, document: document, note: note, options: options)
            return .data(Data(text.utf8))

        case .json:
            return .data(try document.encoded())

        case .html:
            let full = try await renderFullHTML(document: document, title: title, note: note, options: options)
            return .data(Data(full.utf8))

        case .rtf:
            let full = try await renderFullHTML(document: document, title: title, note: note, options: options)
            return .data(try RTFExporter.exportRTF(html: full))

        case .rtfd:
            let full = try await renderFullHTML(document: document, title: title, note: note, options: options)
            return .fileWrapper(try RTFExporter.exportRTFD(html: full))

        case .pdf:
            let full = try await renderFullHTML(document: document, title: title, note: note, options: options)
            return .data(try await PDFExporter.export(html: full, pageSize: options.pageSize.pointSize))

        case .docx:
            return .data(try DocxExporter.export(title: title, document: document, note: note, options: options))
        }
    }

    private func renderFullHTML(document: EditorDocument, title: String, note: Note?, options: ExportOptions) async throws -> String {
        let renderer = DocumentHTMLRenderer()
        let body = await renderer.renderBodyHTML(document: document, isDark: options.theme.isDark)
        return ExportHTMLTemplate.wrap(title: title, bodyFragment: body, note: note, options: options)
    }
}
