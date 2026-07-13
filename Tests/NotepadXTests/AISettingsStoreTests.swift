import XCTest
@testable import NotepadX

final class AISettingsStoreTests: XCTestCase {
    private var store: AISettingsStore!
    private static let settingsDefaultsKey = "NotepadX.aiSettings"

    override func setUpWithError() throws {
        store = AISettingsStore()
        UserDefaults.standard.removeObject(forKey: Self.settingsDefaultsKey)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: Self.settingsDefaultsKey)
    }

    func testSettingsRoundTripThroughUserDefaults() {
        var settings = AISettings()
        settings.modelID = "gpt-4o"
        settings.temperature = 0.3
        settings.systemInstruction = "간결하게 답하라"
        store.save(settings)

        let loaded = store.loadSettings()
        XCTAssertEqual(loaded.modelID, "gpt-4o")
        XCTAssertEqual(loaded.temperature, 0.3)
        XCTAssertEqual(loaded.systemInstruction, "간결하게 답하라")
    }

    func testLoadSettingsReturnsDefaultsWhenNothingSaved() {
        let loaded = store.loadSettings()
        XCTAssertEqual(loaded, AISettings())
    }

    func testSavingSettingsNeverIncludesAPIKeyField() {
        // AISettings 자체에는 apiKey 프로퍼티가 없다 — 인코딩된 JSON에 어떤 키 문자열도
        // 없어야 한다는 것을 구조적으로 보장한다. API 키는 오직 OPENAI_API_KEY 환경 변수로만
        // 읽고, AISettingsStore는 그 값을 저장하지도, 다루지도 않는다.
        let settings = AISettings()
        let data = try! JSONEncoder().encode(settings)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.lowercased().contains("apikey"))
        XCTAssertFalse(json.lowercased().contains("api_key"))
    }
}
