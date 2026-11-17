import CryptoKit
import Foundation
import PocketCastsUtils
import Security

struct DropboxOAuthAttempt {
    static let scopes = ["account_info.read", "files.metadata.read", "files.content.read"]
    let configuration: BooksConfiguration
    let verifier: String
    let state: String

    init(configuration: BooksConfiguration) throws {
        self.configuration = configuration
        verifier = try Self.randomString()
        state = try Self.randomString()
    }

    var authorizationURL: URL {
        var components = URLComponents(string: "https://www.dropbox.com/oauth2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "token_access_type", value: "offline"),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.challenge(verifier)),
            URLQueryItem(name: "state", value: state)
        ]
        return components.url!
    }

    func code(from callback: URL) throws -> String {
        guard callback.scheme == configuration.callbackScheme, callback.host == "oauth", callback.path.isEmpty || callback.path == "/",
              let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
              items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state,
              !items.contains(where: { $0.name == "error" }),
              items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw BooksError.authorization }
        return code
    }

    static func challenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }

    private static func randomString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw BooksError.authorization }
        return Data(bytes).base64URLEncoded()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

protocol BooksCredentialStore {
    func read() throws -> Data?
    func write(_ data: Data?) throws
}

struct BooksKeychainStore: BooksCredentialStore {
    let clientID: String
    private var key: String { "personalBooks.dropbox." + clientID }

    func read() throws -> Data? {
        try KeychainHelper.string(for: key).flatMap { Data(base64Encoded: $0) }
    }

    func write(_ data: Data?) throws {
        if let data {
            guard KeychainHelper.save(string: data.base64EncodedString(), key: key, accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) else { throw BooksError.authorization }
        } else {
            // Missing items already satisfy disconnect; do not treat errSecItemNotFound as a failure.
            if try KeychainHelper.string(for: key) != nil, !KeychainHelper.removeKey(key) { throw BooksError.authorization }
        }
    }
}

actor DropboxOAuth {
    private struct Credentials: Codable {
        let accessToken: String
        let refreshToken: String
        let accountID: String
        let expiresAt: Date
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
        let account_id: String?
        let scope: String?
    }

    private let configuration: BooksConfiguration
    private let store: BooksCredentialStore
    private let session: URLSession
    private var credentials: Credentials?
    private var loaded = false
    private var refreshTask: Task<Credentials, Error>?
    private var refreshID: UUID?
    private var generation = 0

    init(configuration: BooksConfiguration, store: BooksCredentialStore? = nil, session: URLSession = .shared) {
        self.configuration = configuration
        self.store = store ?? BooksKeychainStore(clientID: configuration.clientID)
        self.session = session
    }

    func isConnected() throws -> Bool { try readCredentials() != nil }

    func accountID() throws -> String {
        guard let credentials = try readCredentials() else { throw BooksError.authorization }
        return credentials.accountID
    }

    func accessToken() async throws -> String {
        guard let saved = try readCredentials() else { throw BooksError.authorization }
        if saved.expiresAt > Date().addingTimeInterval(60) { return saved.accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }
        let refreshID = UUID()
        self.refreshID = refreshID
        let generation = self.generation
        let task = Task {
            let refreshed = try await self.fetchToken(fields: ["grant_type": "refresh_token", "refresh_token": saved.refreshToken, "client_id": self.configuration.clientID], previous: saved)
            guard generation == self.generation, self.credentials != nil else { throw BooksError.authorization }
            try self.save(refreshed)
            return refreshed
        }
        refreshTask = task
        defer { if self.refreshID == refreshID { refreshTask = nil; self.refreshID = nil } }
        return try await task.value.accessToken
    }

    func connect(attempt: DropboxOAuthAttempt, callback: URL) async throws {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = nil
        let generation = self.generation
        let code = try attempt.code(from: callback)
        let credentials = try await fetchToken(fields: [
            "grant_type": "authorization_code", "client_id": configuration.clientID,
            "code": code, "code_verifier": attempt.verifier, "redirect_uri": configuration.redirectURI
        ], previous: nil)
        guard generation == self.generation else { throw CancellationError() }
        try save(credentials)
    }

    func disconnect() throws {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = nil
        try store.write(nil)
        credentials = nil
        loaded = true
    }

    static func formData(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let body = fields.keys.sorted().map { key in
            key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + fields[key]!.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    private func readCredentials() throws -> Credentials? {
        if !loaded {
            if let data = try store.read() { credentials = try JSONDecoder().decode(Credentials.self, from: data) }
            loaded = true
        }
        return credentials
    }

    private func save(_ value: Credentials) throws {
        try store.write(JSONEncoder().encode(value))
        credentials = value
        loaded = true
    }

    private func fetchToken(fields: [String: String], previous: Credentials?) async throws -> Credentials {
        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/oauth2/token")!)
        request.httpMethod = "POST"
        request.httpBody = Self.formData(fields)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw BooksError.invalidResponse }
        if [400, 401, 403].contains(response.statusCode) { throw BooksError.authorization }
        guard response.statusCode == 200 else { throw BooksError.invalidResponse }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        if previous == nil {
            let scopes = Set((token.scope ?? "").split(separator: " ").map(String.init))
            guard Set(DropboxOAuthAttempt.scopes).isSubset(of: scopes) else { throw BooksError.authorization }
        }
        guard !token.access_token.isEmpty, token.expires_in.isFinite, token.expires_in > 0,
              let refresh = token.refresh_token ?? previous?.refreshToken, !refresh.isEmpty,
              let account = token.account_id ?? previous?.accountID, !account.isEmpty else { throw BooksError.authorization }
        return Credentials(accessToken: token.access_token, refreshToken: refresh, accountID: account, expiresAt: Date().addingTimeInterval(token.expires_in))
    }
}
