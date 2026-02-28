import XCTest
@testable import Storage

final class DatabaseManagerTests: XCTestCase {
    func testDatabaseManagerSharedInstance() {
        let manager = DatabaseManager.shared
        XCTAssertFalse(manager.databasePath.isEmpty)
        XCTAssertTrue(manager.databasePath.contains("Readless"))
        XCTAssertTrue(manager.databasePath.hasSuffix("readless.sqlite"))
    }
}
