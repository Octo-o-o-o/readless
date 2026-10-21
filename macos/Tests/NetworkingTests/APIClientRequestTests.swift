import XCTest
@testable import Networking

final class APIClientRequestTests: XCTestCase {
    private func XCTAssertPathMatches(
        _ actual: String?,
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            actual?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            expected.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            file: file,
            line: line
        )
    }

    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    private func makeClient(
        authToken: String? = nil,
        refreshCoordinator: AuthRefreshCoordinator = AuthRefreshCoordinator()
    ) -> APIClient {
        APIClient(
            baseURL: URL(string: "https://api.readless.test")!,
            authToken: authToken,
            session: URLProtocolStub.makeSession(),
            refreshCoordinator: refreshCoordinator
        )
    }

    private func contentListJSON() -> Data {
        Data(
            """
            [
              {
                "id": "content-1",
                "title": "Async Swift",
                "source_url": "https://example.com/1",
                "source_type": "text",
                "source_app_name": null,
                "source_app_bundle_id": null,
                "source_language": "en",
                "l0_summary": "Summary",
                "tags": ["swift"],
                "status": "ready",
                "created_at": "2026-03-25T00:00:00Z",
                "updated_at": "2026-03-25T00:00:00Z",
                "podcast_url": null
              }
            ]
            """.utf8
        )
    }

    func testListContentsSendsAuthorizationHeaderAndDecodesResponse() async throws {
        URLProtocolStub.responseHandler = { request in
            self.XCTAssertPathMatches(request.url?.path, "/api/v1/content/")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer secret-token"
            )
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                self.contentListJSON()
            )
        }

        let client = makeClient(authToken: "secret-token")
        let contents = try await client.listContents()

        XCTAssertEqual(contents.count, 1)
        XCTAssertEqual(contents[0].id, "content-1")
        XCTAssertEqual(contents[0].sourceType, .text)
        XCTAssertEqual(contents[0].tags, ["swift"])
    }

    func testRequestMapsUnauthorizedBackendDetailWithoutRefresh() async {
        URLProtocolStub.responseHandler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(#"{"detail":"Session expired"}"#.utf8)
            )
        }

        let client = makeClient(authToken: nil)

        do {
            _ = try await client.healthCheck()
            XCTFail("Expected unauthorized error")
        } catch let error as APIError {
            switch error {
            case .unauthorized(let message):
                XCTAssertEqual(message, "Session expired")
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRequestRetriesAfterRefreshNotificationSucceeds() async throws {
        let notificationCenter = NotificationCenter()
        let refreshCoordinator = AuthRefreshCoordinator(
            notificationCenter: notificationCenter,
            timeout: .seconds(1)
        )
        let client = makeClient(
            authToken: "expired-token",
            refreshCoordinator: refreshCoordinator
        )

        var requestCount = 0
        URLProtocolStub.responseHandler = { request in
            requestCount += 1
            let token = request.value(forHTTPHeaderField: "Authorization")
            if token == "Bearer expired-token" {
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 401,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data(#"{"detail":"expired"}"#.utf8)
                )
            }
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }

        let observer = notificationCenter.addObserver(
            forName: .refreshAuthToken,
            object: nil,
            queue: nil
        ) { _ in
            client.authToken = "fresh-token"
            notificationCenter.post(
                name: .authTokenRefreshCompleted,
                object: nil,
                userInfo: ["success": true]
            )
        }
        defer { notificationCenter.removeObserver(observer) }

        let isHealthy = try await client.healthCheck()
        XCTAssertTrue(isHealthy)
        XCTAssertEqual(requestCount, 2)
    }

    func testHealthCheckWrapsTransportFailureAsNetworkError() async {
        URLProtocolStub.error = URLError(.notConnectedToInternet)
        let client = makeClient()

        do {
            _ = try await client.healthCheck()
            XCTFail("Expected network error")
        } catch let error as APIError {
            switch error {
            case .networkError(let underlying as URLError):
                XCTAssertEqual(underlying.code, .notConnectedToInternet)
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchUserTagsDecodesSnakeCasePayload() async throws {
        URLProtocolStub.responseHandler = { request in
            self.XCTAssertPathMatches(request.url?.path, "/api/v1/tags/")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(
                    """
                    [
                      {
                        "id": 1,
                        "tag_name": "AI",
                        "content_count": 4,
                        "created_at": "2026-03-25T00:00:00Z"
                      }
                    ]
                    """.utf8
                )
            )
        }

        let client = makeClient()
        let tags = try await client.fetchUserTags()

        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags[0].tagName, "AI")
        XCTAssertEqual(tags[0].contentCount, 4)
    }

    func testLoginDecodesAuthResponse() async throws {
        URLProtocolStub.responseHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/auth/login")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(
                    """
                    {
                      "access_token": "access",
                      "refresh_token": "refresh",
                      "expires_in": 900,
                      "user": {
                        "id": "12345678-1234-1234-1234-1234567890ab",
                        "email": "user@example.com",
                        "subscription_tier": "trial",
                        "trial_expires_at": "2026-03-30T00:00:00Z",
                        "subscription_expires_at": null,
                        "email_verified": true,
                        "created_at": "2026-03-25T00:00:00Z"
                      }
                    }
                    """.utf8
                )
            )
        }

        let client = makeClient()
        let response = try await client.login(email: "user@example.com", password: "pw")

        XCTAssertEqual(response.accessToken, "access")
        XCTAssertEqual(response.refreshToken, "refresh")
        XCTAssertEqual(response.user.email, "user@example.com")
        XCTAssertEqual(response.user.subscriptionTier, .trial)
    }

    func testVerifyReceiptDecodesSubscriptionResponse() async throws {
        URLProtocolStub.responseHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/subscription/verify-receipt")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(
                    """
                    {
                      "subscription_tier": "pro",
                      "expires_at": "2026-04-25T00:00:00Z",
                      "is_trial": false,
                      "product_id": "com.readless.pro.monthly"
                    }
                    """.utf8
                )
            )
        }

        let client = makeClient()
        let response = try await client.verifyReceipt(
            transactionId: "txn-1",
            verificationData: "receipt",
            productId: "com.readless.pro.monthly"
        )

        XCTAssertEqual(response.subscriptionTier, "pro")
        XCTAssertEqual(response.productId, "com.readless.pro.monthly")
        XCTAssertFalse(response.isTrial)
    }

    func testHTTPTransportRejectsNonHTTPResponses() async {
        URLProtocolStub.responseHandler = { request in
            (
                URLResponse(
                    url: request.url!,
                    mimeType: nil,
                    expectedContentLength: 0,
                    textEncodingName: nil
                ),
                Data()
            )
        }

        let transport = HTTPTransport(session: URLProtocolStub.makeSession())
        let request = URLRequest(url: URL(string: "https://api.readless.test/health")!)

        do {
            _ = try await transport.send(request)
            XCTFail("Expected invalid response type failure")
        } catch let error as APIError {
            switch error {
            case .serverError(let code, let message):
                XCTAssertEqual(code, 0)
                XCTAssertEqual(message, "Invalid response type")
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
