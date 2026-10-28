import XCTest
@testable import NotepadX

final class AppConfigTests: XCTestCase {
    /// 앱 이름을 바꿨을 때 데이터 폴더가 따라 바뀌면 기존 메모가 사라진 것처럼 보인다.
    func testDataDirectoryIsIndependentOfDisplayName() {
        XCTAssertEqual(AppConfig.dataDirectoryName, "NotepadX")
        XCTAssertTrue(AppConfig.applicationSupportDirectoryName.hasPrefix("NotepadX"))
        XCTAssertNotEqual(AppConfig.dataDirectoryName, AppConfig.displayName)
    }

    func testDatabaseFileNameIsStable() {
        XCTAssertEqual(AppConfig.databaseFileName, "NotepadX.sqlite")
    }
}
