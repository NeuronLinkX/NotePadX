import Foundation

/// AISettings(모델/URL/온도 등, 비밀 아님)를 UserDefaults에 저장한다. API 키는 여기서
/// 다루지 않는다 — 오직 `OPENAI_API_KEY` 환경 변수로만 읽는다(`LLMUseCase` 참고).
struct AISettingsStore: Sendable {
    private static let settingsDefaultsKey = "NotepadX.aiSettings"

    func loadSettings() -> AISettings {
        guard let data = UserDefaults.standard.data(forKey: Self.settingsDefaultsKey),
              let decoded = try? JSONDecoder().decode(AISettings.self, from: data) else {
            return AISettings()
        }
        return decoded
    }

    func save(_ settings: AISettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsDefaultsKey)
    }
}
