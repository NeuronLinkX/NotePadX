import Foundation

struct LLMUseCase: Sendable {
    /// 정적 등록용 환경 변수 이름. README에 그대로 문서화되어 있다.
    static let environmentVariableName = "OPENAI_API_KEY"

    private let store: AISettingsStore
    private let client: OpenAIClient

    init(store: AISettingsStore = AISettingsStore(), client: OpenAIClient = OpenAIClient()) {
        self.store = store
        self.client = client
    }

    /// API 키는 오직 `OPENAI_API_KEY` 환경 변수로만 읽는다 — 앱 안에 입력해서 저장하는
    /// 경로는 없다. Finder/Dock에서 실행하는 GUI 앱은 셸 rc 파일을 읽지 않으므로,
    /// `launchctl setenv` 또는 Xcode 스킴 환경 변수로 등록해야 실제로 적용된다.
    private static func environmentAPIKey() -> String? {
        guard let value = ProcessInfo.processInfo.environment[environmentVariableName] else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func currentSettings() -> AISettings {
        store.loadSettings()
    }

    func hasAPIKey() -> Bool {
        Self.environmentAPIKey() != nil
    }

    func maskedAPIKey() -> String? {
        guard let key = Self.environmentAPIKey() else { return nil }
        guard key.count > 8 else { return String(repeating: "•", count: key.count) }
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        return "\(prefix)\(String(repeating: "•", count: max(0, key.count - 8)))\(suffix)"
    }

    func saveSettings(_ settings: AISettings) {
        store.save(settings)
    }

    private func resolvedAPIKey() throws -> String {
        guard let key = Self.environmentAPIKey() else { throw AIClientError.missingAPIKey }
        return key
    }

    func testConnection() async throws {
        let settings = store.loadSettings()
        let key = try resolvedAPIKey()
        try await client.testConnection(settings: settings, apiKey: key)
    }

    /// 전송 전 미리보기에 쓸 예상 전송 문자 수 (스펙 16절).
    static func estimatedCharacterCount(content: String, task: AITaskType, customPrompt: String) -> Int {
        let instruction = task == .custom ? customPrompt : task.instruction
        return content.count + instruction.count
    }

    func streamResponse(
        task: AITaskType,
        customPrompt: String,
        content: String,
        documentTitle: String,
        codeLanguage: String?
    ) throws -> AsyncThrowingStream<String, Error> {
        let settings = store.loadSettings()
        let key = try resolvedAPIKey()
        let messages = PromptBuilder.buildMessages(
            task: task,
            customPrompt: customPrompt,
            content: content,
            documentTitle: documentTitle,
            codeLanguage: codeLanguage,
            userSystemInstruction: settings.systemInstruction
        )
        return client.streamChatCompletion(messages: messages, settings: settings, apiKey: key)
    }
}
