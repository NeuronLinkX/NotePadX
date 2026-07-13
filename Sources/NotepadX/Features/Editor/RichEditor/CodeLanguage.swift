import Foundation

struct CodeLanguageOption: Identifiable, Hashable {
    let value: String
    let label: String
    var id: String { value }
}

/// WebEditor/src/languages.js의 SUPPORTED_LANGUAGES와 동일한 목록을 유지한다 (스펙 7절).
enum CodeLanguage {
    static let all: [CodeLanguageOption] = [
        CodeLanguageOption(value: "c", label: "C"),
        CodeLanguageOption(value: "cpp", label: "C++"),
        CodeLanguageOption(value: "rust", label: "Rust"),
        CodeLanguageOption(value: "swift", label: "Swift"),
        CodeLanguageOption(value: "python", label: "Python"),
        CodeLanguageOption(value: "java", label: "Java"),
        CodeLanguageOption(value: "javascript", label: "JavaScript"),
        CodeLanguageOption(value: "typescript", label: "TypeScript"),
        CodeLanguageOption(value: "json", label: "JSON"),
        CodeLanguageOption(value: "yaml", label: "YAML"),
        CodeLanguageOption(value: "xml", label: "XML"),
        CodeLanguageOption(value: "html", label: "HTML"),
        CodeLanguageOption(value: "css", label: "CSS"),
        CodeLanguageOption(value: "bash", label: "Bash"),
        CodeLanguageOption(value: "sql", label: "SQL"),
        CodeLanguageOption(value: "cmake", label: "CMake"),
        CodeLanguageOption(value: "markdown", label: "Markdown"),
        CodeLanguageOption(value: "plaintext", label: "Plain Text"),
    ]
}
