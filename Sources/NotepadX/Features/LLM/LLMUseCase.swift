import Foundation

/// API 키가 지금 어디서 오고 있는지 — 설정 화면에 그대로 보여주기 위한 값이다.
enum APIKeySource: Sendable, Equatable {
    case keychain
    case environmentVariable
    case none
}

struct LLMUseCase: Sendable {
    /// 폴백용 환경 변수 이름. README에 그대로 문서화되어 있다.
    static let environmentVariableName = "OPENAI_API_KEY"
    private static let keychainAccount = "openAIAPIKey"

    private let store: AISettingsStore
    private let client: OpenAIClient
    private let keychain: KeychainService

    init(
        store: AISettingsStore = AISettingsStore(),
        client: OpenAIClient = OpenAIClient(),
        keychain: KeychainService = KeychainService()
    ) {
        self.store = store
        self.client = client
        self.keychain = keychain
    }

    /// 설정 화면의 "키 등록" 버튼으로 저장한 값. 한 번 등록하면 Keychain에 남아서, 터미널에서
    /// `export`한 환경 변수처럼 앱을 껐다 켜거나 로그아웃해도 사라지지 않는다.
    private func keychainAPIKey() -> String? {
        guard let value = (try? keychain.string(forKey: Self.keychainAccount)) ?? nil else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 레거시/CI용 폴백. Finder/Dock에서 실행하는 GUI 앱은 셸 rc 파일을 읽지 않으므로,
    /// `launchctl setenv` 또는 Xcode 스킴 환경 변수로 등록해야 실제로 적용되고, 재부팅하면
    /// 다시 사라진다 — 그래서 Keychain 등록을 우선으로 쓴다.
    private static func environmentAPIKey() -> String? {
        guard let value = ProcessInfo.processInfo.environment[environmentVariableName] else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Keychain에 등록된 값을 최우선으로 쓰고, 없을 때만 환경 변수로 폴백한다.
    private func resolvedAPIKeySource() -> String? {
        keychainAPIKey() ?? Self.environmentAPIKey()
    }

    func apiKeySource() -> APIKeySource {
        if keychainAPIKey() != nil { return .keychain }
        if Self.environmentAPIKey() != nil { return .environmentVariable }
        return .none
    }

    func currentSettings() -> AISettings {
        store.loadSettings()
    }

    func hasAPIKey() -> Bool {
        resolvedAPIKeySource() != nil
    }

    func maskedAPIKey() -> String? {
        guard let key = resolvedAPIKeySource() else { return nil }
        guard key.count > 8 else { return String(repeating: "•", count: key.count) }
        let prefix = key.prefix(4)
        let suffix = key.suffix(4)
        return "\(prefix)\(String(repeating: "•", count: max(0, key.count - 8)))\(suffix)"
    }

    func saveSettings(_ settings: AISettings) {
        store.save(settings)
    }

    /// 설정 화면의 "키 등록" 버튼이 호출한다 — 한 번 등록되면 사용자가 직접 "키 삭제"를
    /// 누르기 전까지는 바뀌지 않는다.
    func registerAPIKey(_ rawKey: String) throws {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIClientError.missingAPIKey }
        try keychain.setString(trimmed, forKey: Self.keychainAccount)
    }

    func clearStoredAPIKey() throws {
        try keychain.removeValue(forKey: Self.keychainAccount)
    }

    private func resolvedAPIKey() throws -> String {
        guard let key = resolvedAPIKeySource() else { throw AIClientError.missingAPIKey }
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
