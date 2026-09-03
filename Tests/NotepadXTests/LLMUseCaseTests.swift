import XCTest
@testable import NotepadX

/// Keychain 등록(우선)과 `OPENAI_API_KEY` 환경 변수(폴백) 양쪽으로 API 키를 읽는 동작을
/// 검증한다. Keychain은 테스트마다 별도 네임스페이스를 써서 서로 영향을 주지 않게 하고,
/// 실제 프로세스 환경도 건드리므로 테스트가 끝나면 반드시 원래 상태로 되돌린다.
final class LLMUseCaseTests: XCTestCase {
    private var keychain: KeychainService!
    private var useCase: LLMUseCase!
    private var originalEnvValue: String?

    override func setUpWithError() throws {
        keychain = KeychainService(service: "com.notepadx.tests.llmusecase.\(UUID().uuidString)")
        useCase = LLMUseCase(store: AISettingsStore(), client: OpenAIClient(), keychain: keychain)
        originalEnvValue = ProcessInfo.processInfo.environment[LLMUseCase.environmentVariableName]
        unsetenv(LLMUseCase.environmentVariableName)
    }

    override func tearDownWithError() throws {
        if let originalEnvValue {
            setenv(LLMUseCase.environmentVariableName, originalEnvValue, 1)
        } else {
            unsetenv(LLMUseCase.environmentVariableName)
        }
        try? useCase.clearStoredAPIKey()
    }

    func testNoKeyWhenNothingIsRegistered() {
        XCTAssertFalse(useCase.hasAPIKey())
        XCTAssertNil(useCase.maskedAPIKey())
        XCTAssertEqual(useCase.apiKeySource(), .none)
    }

    func testHasKeyWhenEnvironmentVariableIsSet() {
        setenv(LLMUseCase.environmentVariableName, "sk-from-env-0123456789", 1)
        XCTAssertTrue(useCase.hasAPIKey())
        XCTAssertNotNil(useCase.maskedAPIKey())
        XCTAssertEqual(useCase.apiKeySource(), .environmentVariable)
    }

    func testIgnoresBlankEnvironmentVariable() {
        setenv(LLMUseCase.environmentVariableName, "   ", 1)
        XCTAssertFalse(useCase.hasAPIKey())
        XCTAssertNil(useCase.maskedAPIKey())
    }

    func testMaskedKeyHidesMiddleCharacters() {
        setenv(LLMUseCase.environmentVariableName, "sk-abcdefghijklmnop", 1)
        let masked = useCase.maskedAPIKey()
        XCTAssertNotNil(masked)
        XCTAssertTrue(masked!.hasPrefix("sk-a"))
        XCTAssertTrue(masked!.hasSuffix("mnop"))
        XCTAssertFalse(masked!.contains("abcdefghijkl"))
    }

    func testRegisteredKeyPersistsAcrossUseCaseInstances() throws {
        try useCase.registerAPIKey("sk-from-keychain-0123456789")
        XCTAssertTrue(useCase.hasAPIKey())
        XCTAssertEqual(useCase.apiKeySource(), .keychain)

        // 새 LLMUseCase 인스턴스(= 앱을 다시 켠 것과 동등)로도 그대로 남아 있어야 한다 —
        // 이게 "한 번 등록하면 다시 사라지지 않는다"는 요구사항의 핵심이다.
        let restarted = LLMUseCase(store: AISettingsStore(), client: OpenAIClient(), keychain: keychain)
        XCTAssertTrue(restarted.hasAPIKey())
    }

    func testRegisteredKeyTakesPriorityOverEnvironmentVariable() throws {
        setenv(LLMUseCase.environmentVariableName, "sk-from-env-0123456789", 1)
        try useCase.registerAPIKey("sk-from-keychain-0123456789")
        XCTAssertEqual(useCase.apiKeySource(), .keychain)
    }

    func testClearStoredAPIKeyFallsBackToEnvironmentVariable() throws {
        setenv(LLMUseCase.environmentVariableName, "sk-from-env-0123456789", 1)
        try useCase.registerAPIKey("sk-from-keychain-0123456789")
        try useCase.clearStoredAPIKey()
        XCTAssertEqual(useCase.apiKeySource(), .environmentVariable)
    }

    func testRegisteringBlankKeyThrows() {
        XCTAssertThrowsError(try useCase.registerAPIKey("   "))
    }
}
