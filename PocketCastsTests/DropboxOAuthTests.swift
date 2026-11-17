import XCTest
@testable import podcasts

final class DropboxOAuthTests: XCTestCase {
    private let config = BooksConfiguration(clientID: "test-client", namespaceID: "namespace", folderID: "id:folder")
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BooksOAuthURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        BooksOAuthURLProtocol.handler = nil
        super.tearDown()
    }

    func testPKCEUsesKnownRFC7636VectorAndNeverIncludesAClientSecret() throws {
        XCTAssertEqual(DropboxOAuthAttempt.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let attempt = try DropboxOAuthAttempt(configuration: config)
        XCTAssertEqual(attempt.verifier.count, 43)
        let items = try XCTUnwrap(URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first(where: { $0.name == "code_challenge_method" })?.value, "S256")
        XCTAssertEqual(items.first(where: { $0.name == "token_access_type" })?.value, "offline")
        XCTAssertFalse(items.contains(where: { $0.name == "client_secret" || $0.name == "code_verifier" }))
    }

    func testCallbackRejectsWrongStateWrongHostErrorsAndDuplicateValues() throws {
        let attempt = try DropboxOAuthAttempt(configuration: config)
        XCTAssertEqual(try attempt.code(from: callback(attempt)), "test-code")
        for string in [
            "db-test-client://oauth?code=x&state=wrong",
            "db-test-client://other?code=x&state=\(attempt.state)",
            "db-test-client://oauth?error=access_denied&state=\(attempt.state)",
            "db-test-client://oauth?code=x&state=\(attempt.state)&state=\(attempt.state)"
        ] {
            XCTAssertThrowsError(try attempt.code(from: XCTUnwrap(URL(string: string))))
        }
    }

    func testFormEncodingProtectsReservedCharacters() {
        XCTAssertEqual(String(decoding: DropboxOAuth.formData(["code": "a&b+=% value"]), as: UTF8.self), "code=a%26b%2B%3D%25%20value")
    }

    func testRefreshIsSharedByConcurrentRequestsAndRestoredAfterRelaunch() async throws {
        let store = BooksMemoryCredentials()
        var requests = 0
        BooksOAuthURLProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.url?.host, "api.dropboxapi.com")
            if requests == 1 {
                return try self.response(token: "initial", expires: 1, initial: true)
            }
            return try self.response(token: "refreshed", expires: 3600, initial: false)
        }
        let oauth = DropboxOAuth(configuration: config, store: store, session: session)
        let attempt = try DropboxOAuthAttempt(configuration: config)
        try await oauth.connect(attempt: attempt, callback: callback(attempt))
        async let first = oauth.accessToken()
        async let second = oauth.accessToken()
        let tokens = try await [first, second]
        XCTAssertEqual(tokens, ["refreshed", "refreshed"])
        XCTAssertEqual(requests, 2)
        let relaunched = DropboxOAuth(configuration: config, store: store, session: session)
        let restored = try await relaunched.accessToken()
        XCTAssertEqual(restored, "refreshed")
        XCTAssertEqual(requests, 2)
        try await relaunched.disconnect()
        XCTAssertNil(try store.read())
    }

    func testCredentialWriteFailureDoesNotReportAConnectedAccount() async throws {
        let store = BooksMemoryCredentials()
        store.failWrite = true
        BooksOAuthURLProtocol.handler = { _ in try self.response(token: "initial", expires: 3600, initial: true) }
        let oauth = DropboxOAuth(configuration: config, store: store, session: session)
        let attempt = try DropboxOAuthAttempt(configuration: config)
        do {
            try await oauth.connect(attempt: attempt, callback: callback(attempt))
            XCTFail("Cannot complete connection when credentials cannot be persisted")
        } catch {}
        let connected = try await oauth.isConnected()
        XCTAssertFalse(connected)
    }

    private func callback(_ attempt: DropboxOAuthAttempt) throws -> URL {
        try XCTUnwrap(URL(string: config.redirectURI + "?code=test-code&state=" + attempt.state))
    }

    private func response(token: String, expires: Int, initial: Bool) throws -> Data {
        var response: [String: Any] = ["access_token": token, "expires_in": expires]
        if initial {
            response["refresh_token"] = "refresh"
            response["account_id"] = "account"
            response["scope"] = DropboxOAuthAttempt.scopes.joined(separator: " ")
        }
        return try JSONSerialization.data(withJSONObject: response)
    }
}

private final class BooksMemoryCredentials: BooksCredentialStore {
    var data: Data?
    var failWrite = false
    func read() throws -> Data? { data }
    func write(_ data: Data?) throws {
        if failWrite { throw BooksError.authorization }
        self.data = data
    }
}

private final class BooksOAuthURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        do {
            let data = try XCTUnwrap(Self.handler)(request)
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}
