import SwiftUI

/// 검색 결과 미리보기에서 일치한 부분을 강조한다 (스펙 12절).
/// FTS5의 snippet()은 trigram 토크나이저와 궁합이 나빠(3글자 창 단위로 잘림) 쓰지 않고,
/// Swift 쪽에서 원본 질의로 다시 대소문자 무시 부분일치를 찾아 강조 구간을 만든다.
enum SearchSnippetBuilder {
    static func makeSnippet(from text: String, query: String, contextLength: Int = 40) -> AttributedString {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty,
              let range = text.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) else {
            let collapsed = text.replacingOccurrences(of: "\n", with: " ")
            return AttributedString(String(collapsed.prefix(100)))
        }

        let start = text.index(range.lowerBound, offsetBy: -contextLength, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: contextLength, limitedBy: text.endIndex) ?? text.endIndex

        let prefixText = String(text[start..<range.lowerBound]).replacingOccurrences(of: "\n", with: " ")
        let matchText = String(text[range])
        let suffixText = String(text[range.upperBound..<end]).replacingOccurrences(of: "\n", with: " ")

        var result = AttributedString((start == text.startIndex ? "" : "…") + prefixText)

        var matched = AttributedString(matchText)
        matched.backgroundColor = .yellow.opacity(0.45)
        matched.foregroundColor = .primary
        result += matched

        result += AttributedString(suffixText + (end == text.endIndex ? "" : "…"))
        return result
    }
}
