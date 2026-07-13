import Foundation

enum PlainTextExporter {
    static func export(title: String, plainText: String, note: Note?, options: ExportOptions) -> String {
        var lines: [String] = []
        if options.includeTitle, !title.isEmpty {
            lines.append(title)
            lines.append(String(repeating: "=", count: min(title.count, 60)))
            lines.append("")
        }
        if options.includeDates, let note {
            lines.append("생성: \(DateFormatting.export.string(from: note.createdAt))")
            lines.append("수정: \(DateFormatting.export.string(from: note.updatedAt))")
            lines.append("")
        }
        lines.append(plainText)
        return lines.joined(separator: "\n")
    }
}
