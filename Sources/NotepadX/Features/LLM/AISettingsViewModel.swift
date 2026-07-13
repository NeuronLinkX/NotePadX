import Foundation

@MainActor
final class AISettingsViewModel: ObservableObject {
    @Published var settings: AISettings
    @Published private(set) var hasAPIKey: Bool
    @Published private(set) var maskedKey: String?
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
    }

    func saveSettings() {
        llmUseCase.saveSettings(settings)
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
