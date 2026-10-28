import Foundation

struct ImportSummary: Sendable, Equatable {
    struct Failure: Sendable, Equatable {
        let name: String
        let reason: String
    }

    var importedIDs: [UUID] = []
    var failures: [Failure] = []
    /// 가져왔지만 옮기지 못한 요소가 있는 파일: "파일 이름: 그림 2개, 각주 1개".
    var warnings: [String] = []

    var isEmpty: Bool { importedIDs.isEmpty && failures.isEmpty }

    /// 결과 알림에 그대로 보여 줄 문장.
    var message: String {
        var lines: [String] = []
        if !importedIDs.isEmpty { lines.append("메모 \(importedIDs.count)개를 가져왔습니다.") }
        if !warnings.isEmpty {
            lines.append("")
            lines.append("일부 요소는 옮기지 못했습니다:")
            lines.append(contentsOf: warnings.map { "• \($0)" })
        }
        if !failures.isEmpty {
            lines.append("")
            lines.append("가져오지 못한 항목:")
            lines.append(contentsOf: failures.map { "• \($0.name) — \($0.reason)" })
        }
        return lines.joined(separator: "\n")
    }
}

/// 파일(.md/.markdown/.txt/.docx)과 Apple 메모에서 메모를 만든다. 가져온 것은 항상 **새 메모**로 들어가며
/// 기존 메모는 건드리지 않는다.
struct NoteImportService: Sendable {
    static let supportedExtensions: Set<String> = ["md", "markdown", "txt", "text", "docx"]
    static let maxTextBytes = 10 * 1024 * 1024
    static let maxDocxBytes = 64 * 1024 * 1024

    let noteUseCase: NoteUseCase

    func importFiles(_ urls: [URL], folderID: UUID?) async -> ImportSummary {
        var summary = ImportSummary()
        for url in urls {
            let name = url.lastPathComponent
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let (imported, warnings) = try Self.load(url)
                let id = try await store(imported, folderID: folderID)
                summary.importedIDs.append(id)
                if !warnings.isEmpty { summary.warnings.append("\(name): " + warnings.joined(separator: ", ")) }
            } catch let error as ImportError {
                summary.failures.append(.init(name: name, reason: error.description))
            } catch {
                summary.failures.append(.init(name: name, reason: "읽거나 저장하지 못했습니다 (\(error.localizedDescription))"))
            }
        }
        announce(summary)
        return summary
    }

    func importAppleNotes(fetcher: AppleNotesFetching, folderID: UUID?) async -> ImportSummary {
        var summary = ImportSummary()
        do {
            let notes = try await fetcher.fetchNotes()
            for (index, raw) in notes.enumerated() {
                let imported = HTMLNoteConverter.importedNote(name: raw.title, html: raw.html, fallbackTitle: "Apple 메모 \(index + 1)")
                do {
                    summary.importedIDs.append(try await store(imported, folderID: folderID))
                } catch {
                    summary.failures.append(.init(name: raw.title, reason: "저장하지 못했습니다 (\(error.localizedDescription))"))
                }
            }
            if notes.isEmpty { summary.failures.append(.init(name: "Apple 메모", reason: "가져올 메모가 없습니다")) }
        } catch let error as AppleNotesError {
            summary.failures.append(.init(name: "Apple 메모", reason: error.description))
        } catch {
            summary.failures.append(.init(name: "Apple 메모", reason: error.localizedDescription))
        }
        announce(summary)
        return summary
    }

    // MARK: -

    enum ImportError: Error, CustomStringConvertible {
        case unsupported(String)
        case tooLarge(Int)
        case unreadableText
        case docx(DocxImporter.DocxError)

        var description: String {
            switch self {
            case .unsupported(let ext): return "지원하지 않는 형식입니다 (.\(ext)). .md, .txt, .docx만 가져올 수 있어요"
            case .tooLarge(let mb): return "파일이 너무 큽니다 (\(mb)MB)"
            case .unreadableText: return "글자 인코딩을 알 수 없어 읽지 못했습니다"
            case .docx(.notADocx): return "올바른 Word(.docx) 파일이 아닙니다 (암호가 걸려 있거나 오래된 .doc 형식일 수 있어요)"
            case .docx(.encrypted): return "암호가 걸린 파일이라 읽지 못했습니다"
            case .docx(.unreadable(let detail)): return "문서를 해석하지 못했습니다 (\(detail))"
            }
        }
    }

    /// 파일 하나를 읽어 가져온 메모로 바꾼다(저장은 하지 않는다 — 시험하기 쉽게 분리).
    static func load(_ url: URL) throws -> (ImportedNote, [String]) {
        let ext = url.pathExtension.lowercased()
        let title = url.deletingPathExtension().lastPathComponent
        guard supportedExtensions.contains(ext) else { throw ImportError.unsupported(ext) }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        switch ext {
        case "docx":
            guard size <= maxDocxBytes else { throw ImportError.tooLarge(size / 1_048_576) }
            let data = try Data(contentsOf: url)
            do {
                let result = try DocxImporter.importDocument(from: data, fallbackTitle: title)
                return (result.note, result.skippedFeatures)
            } catch let error as DocxImporter.DocxError {
                throw ImportError.docx(error)
            }
        default:
            guard size <= maxTextBytes else { throw ImportError.tooLarge(size / 1_048_576) }
            let text = try decodeText(Data(contentsOf: url))
            let isMarkdown = ext == "md" || ext == "markdown"
            return (isMarkdown ? MarkdownImporter.parse(text, fallbackTitle: title) : MarkdownImporter.parsePlainText(text, fallbackTitle: title), [])
        }
    }

    /// UTF-8(BOM 포함), UTF-16, 그다음 한국어 Windows에서 흔한 EUC-KR(CP949) 순으로 시도한다.
    static func decodeText(_ data: Data) throws -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let s = String(data: data.dropFirst(3), encoding: .utf8) { return s }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let s = String(data: data, encoding: .utf16) { return s }
        if let s = String(data: data, encoding: .utf8) { return s }
        let eucKR = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)))
        if let s = String(data: data, encoding: eucKR) { return s }
        throw ImportError.unreadableText
    }

    private func store(_ imported: ImportedNote, folderID: UUID?) async throws -> UUID {
        var note = try await noteUseCase.createNote(folderID: folderID)
        note = try noteUseCase.applyEdit(to: note, title: imported.title, document: imported.document, plainText: imported.plainText)
        try await noteUseCase.save(note)
        return note.id
    }

    private func announce(_ summary: ImportSummary) {
        guard !summary.importedIDs.isEmpty else { return }
        NotificationCenter.default.post(name: .notesChangedExternally, object: nil, userInfo: ["ids": summary.importedIDs])
    }
}
