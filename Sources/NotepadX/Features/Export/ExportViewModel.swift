import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ExportViewModel: ObservableObject {
    @Published var format: ExportFormat = .markdown
    @Published var options = ExportOptions()
    @Published var isExporting = false
    @Published var errorMessage: String?
    @Published private(set) var lastExportedURL: URL?

    private let exportUseCase = ExportUseCase()

    /// 저장 위치를 먼저 물어보고(사용자가 취소하면 아무 작업도 하지 않음), 그다음에
    /// 실제 변환(렌더링이 필요한 HTML/PDF/RTF는 시간이 걸릴 수 있음)을 수행한다.
    func exportAndSave(note: Note, title: String, document: EditorDocument) async {
        let suggestedName = FileNameSanitizer.sanitize(title.isEmpty ? note.displayTitle : title)
        guard let url = presentSavePanel(suggestedName: suggestedName) else { return }

        isExporting = true
        errorMessage = nil
        do {
            let output = try await exportUseCase.export(note: note, title: title, document: document, format: format, options: options)
            switch output {
            case .data(let data):
                try data.write(to: url, options: .atomic)
            case .fileWrapper(let wrapper):
                try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
            }
            lastExportedURL = url
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isExporting = false
    }

    private func presentSavePanel(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(suggestedName).\(format.fileExtension)"
        panel.allowedContentTypes = [resolvedUTType()]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func resolvedUTType() -> UTType {
        UTType(format.utType) ?? UTType(filenameExtension: format.fileExtension) ?? .data
    }

    func revealInFinder() {
        guard let url = lastExportedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openInDefaultApp() {
        guard let url = lastExportedURL else { return }
        NSWorkspace.shared.open(url)
    }

    func attachToEmail() {
        guard let url = lastExportedURL, let service = NSSharingService(named: .composeEmail) else { return }
        service.perform(withItems: [url])
    }
}
