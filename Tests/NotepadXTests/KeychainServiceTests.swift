import XCTest
@testable import NotepadX

final class KeychainServiceTests: XCTestCase {
    private var service: KeychainService!
    private let key = "unitTestKey"

    override func setUpWithError() throws {
        // 테스트끼리 서로 다른 keychain "service" 네임스페이스를 쓰게 해서 병렬 실행이나
        // 이전 실패로 남은 값이 다른 테스트에 영향을 주지 않게 한다.
        service = KeychainService(service: "com.notepadx.tests.\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? service.removeValue(forKey: key)
    }

    func testSetAndReadStringRoundTrips() throws {
        try service.setString("hello-secret", forKey: key)
        let value = try service.string(forKey: key)
        XCTAssertEqual(value, "hello-secret")
    }

    func testOverwritingExistingValueUpdatesInPlace() throws {
        try service.setString("first", forKey: key)
        try service.setString("second", forKey: key)
        let value = try service.string(forKey: key)
        XCTAssertEqual(value, "second")
    }

    func testMissingKeyReturnsNilNotError() throws {
        let value = try service.string(forKey: "neverSetKey")
        XCTAssertNil(value)
    }

    func testRemoveValueDeletesEntry() throws {
        try service.setString("to-delete", forKey: key)
        try service.removeValue(forKey: key)
        let value = try service.string(forKey: key)
        XCTAssertNil(value)
    }

    func testDataRoundTrips() throws {
        let payload = Data([0x01, 0x02, 0x03, 0xFF])
        try service.setData(payload, forKey: key)
        let readBack = try service.data(forKey: key)
        XCTAssertEqual(readBack, payload)
    }
}
