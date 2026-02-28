import XCTest
@testable import Networking

final class APIClientTests: XCTestCase {
    func testAPIClientInitialization() {
        let url = URL(string: "https://api.readless.test")!
        let client = APIClient(baseURL: url, authToken: "test-token")
        XCTAssertEqual(client.baseURL, url)
    }

    func testAPIClientWithoutAuthToken() {
        let url = URL(string: "https://api.readless.test")!
        let client = APIClient(baseURL: url)
        XCTAssertEqual(client.baseURL, url)
    }
}
