import AppKit
import Foundation

/// 완성된 HTML을 NSAttributedString으로 읽어들인 뒤 RTF/RTFD로 다시 쓴다.
/// RTFD는 이미지가 있는 경우를 위한 패키지 형식이며, 텍스트만 있는 문서는 RTF와 사실상 같다.
enum RTFExporter {
    static func exportRTF(html: String) throws -> Data {
        let attributed = try attributedString(fromHTML: html)
        let range = NSRange(location: 0, length: attributed.length)
        return try attributed.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    static func exportRTFD(html: String) throws -> FileWrapper {
        let attributed = try attributedString(fromHTML: html)
        let range = NSRange(location: 0, length: attributed.length)
        return try attributed.fileWrapper(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
    }

    private static func attributedString(fromHTML html: String) throws -> NSAttributedString {
        guard let data = html.data(using: .utf8) else {
            throw AppError.exportFailed(format: "RTF")
        }
        return try NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        )
    }
}
