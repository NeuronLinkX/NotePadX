import Foundation

/// 내보내기 파일명을 정제한다 (스펙 22절: "내보내기 파일명 정제", 경로 순회 방지).
/// 슬래시/콜론 등 경로 구분자와 파일시스템 예약 문자를 제거하고, 지나치게 긴 이름을 자른다.
enum FileNameSanitizer {
    static func sanitize(_ rawName: String, fallback: String = "제목 없음") -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let withoutInvalidChars = rawName.components(separatedBy: invalidCharacters).joined(separator: "-")
        let withoutControlChars = withoutInvalidChars.components(separatedBy: .controlCharacters).joined()
        // ".."나 선행 "."으로 시작하는 이름이 상위 디렉터리로 해석되지 않도록 방지.
        var trimmed = withoutControlChars.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix(".") { trimmed.removeFirst() }

        // "///"처럼 구분자만 있던 입력은 치환 후 "---"가 되어 isEmpty로는 못 걸러진다.
        // 대시만 남았는지도 함께 확인한다.
        let meaningfulContent = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if meaningfulContent.isEmpty { return fallback }
        return String(trimmed.prefix(150))
    }
}
