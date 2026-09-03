import Foundation

@MainActor
final class AISettingsViewModel: ObservableObject {
    @Published var settings: AISettings
    @Published private(set) var hasAPIKey: Bool
    @Published private(set) var maskedKey: String?
    @Published private(set) var apiKeySource: APIKeySource
    @Published var apiKeyInput: String = ""
    @Published var isTestingConnection = false
    @Published var testResultMessage: String?
    @Published var testSucceeded: Bool?
    @Published var errorMessage: String?

    static var environmentVariableName: String { LLMUseCase.environmentVariableName }

    private let llmUseCase: LLMUseCase

    init(llmUseCase: LLMUseCase = LLMUseCase()) {
        self.llmUseCase = llmUseCase
        self.settings = llmUseCase.currentSettings()
        self.hasAPIKey = llmUseCase.hasAPIKey()
        self.maskedKey = llmUseCase.maskedAPIKey()
        self.apiKeySource = llmUseCase.apiKeySource()
    }

    func saveSettings() {
        llmUseCase.saveSettings(settings)
    }

    /// "키 등록" 버튼 — 한 번 등록하면 Keychain에 고정되어, 이후에는 앱을 다시 켜거나
    /// 로그아웃해도 다시 입력할 필요가 없다.
    func registerAPIKey() {
        do {
            try llmUseCase.registerAPIKey(apiKeyInput)
            apiKeyInput = ""
            refreshAPIKeyState()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 등록된 키를 지운다 — 키를 바꾸고 싶을 때 먼저 이걸 눌러야 한다.
    func clearStoredAPIKey() {
        do {
            try llmUseCase.clearStoredAPIKey()
            refreshAPIKeyState()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func refreshAPIKeyState() {
        hasAPIKey = llmUseCase.hasAPIKey()
        maskedKey = llmUseCase.maskedAPIKey()
        apiKeySource = llmUseCase.apiKeySource()
    }

    func testConnection() async {
        isTestingConnection = true
        testResultMessage = nil
        testSucceeded = nil
        saveSettings()
        do {
            try await llmUseCase.testConnection()
            testSucceeded = true
            testResultMessage = "연결에 성공했습니다."
        } catch {
            testSucceeded = false
            testResultMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isTestingConnection = false
    }
}
