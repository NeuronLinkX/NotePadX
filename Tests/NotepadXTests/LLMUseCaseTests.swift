import XCTest
@testable import NotepadX

/// `OPENAI_API_KEY` 환경 변수만으로 API 키를 읽는 동작을 검증한다 — 앱 안에 저장하는
/// 경로가 없으므로 이게 유일한 소스다. 실제 프로세스 환경을 건드리므로, 테스트가 끝나면
/// 반드시 원래 상태로 되돌린다.
final class LLMUseCaseTests: XCTestCase {
    private var useCase: LLMUseCase!
    private var originalEnvValue: String?

    override func setUpWithError() throws {
        useCase = LLMUseCase(store: AISettingsStore(), client: OpenAIClient())
        originalEnvValue = ProcessInfo.processInfo.environment[LLMUseCase.environmentVariableName]
        unsetenv(LLMUseCase.environmentVariableName)
    }

    override func tearDownWithError() throws {
        if let originalEnvValue {
            setenv(LLMUseCase.environmentVariableName, originalEnvValue, 1)
        } else {
            unsetenv(LLMUseCase.environmentVariableName)
        }
    }

    func testNoKeyWhenEnvironmentVariableIsUnset() {
        XCTAssertFalse(useCase.hasAPIKey())
        XCTAssertNil(useCase.maskedAPIKey())
    }

    func testHasKeyWhenEnvironmentVariableIsSet() {
        setenv(LLMUseCase.environmentVariableName, "sk-from-env-0123456789", 1)
        XCTAssertTrue(useCase.hasAPIKey())
        XCTAssertNotNil(useCase.maskedAPIKey())
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
}
