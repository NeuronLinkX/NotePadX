import Foundation

enum AIProvider: String, CaseIterable, Identifiable, Sendable, Codable {
    case openAI
    var id: String { rawValue }
    var displayName: String { "OpenAI" }
}

/// 개인용 BYOK(Bring Your Own Key)와 배포용 백엔드 프록시를 구분한다 (스펙 16절).
/// 이 앱은 배포용 백엔드가 없으므로 지금은 `bringYourOwnKey`만 실제로 동작한다 —
/// `backendProxy`는 나중에 서버를 두게 되면 OpenAIClient의 baseURL을 그 서버로만 바꾸면 되도록
/// 타입만 미리 만들어 뒀다.
enum AIAuthenticationMode: String, CaseIterable, Sendable, Codable {
    case bringYourOwnKey
    case backendProxy
}

/// API 키는 여기 포함하지 않는다 — 키는 오직 Keychain에만 있고, 이 struct는 UserDefaults에
/// 저장해도 안전한 "비밀 아닌" 설정만 담는다.
struct AISettings: Sendable, Codable, Equatable {
    var provider: AIProvider = .openAI
    var authenticationMode: AIAuthenticationMode = .bringYourOwnKey
    var modelID: String = "gpt-4o-mini"
    var baseURLString: String = "https://api.openai.com/v1"
    var timeoutSeconds: Double = 60
    var temperature: Double = 0.7
    var maxOutputTokens: Int = 2048
    var systemInstruction: String = ""

    var baseURL: URL? { URL(string: baseURLString) }
}
