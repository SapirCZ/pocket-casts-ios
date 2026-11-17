import XCTest
@testable import podcasts

final class DropboxLibraryClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        LibraryURLProtocol.handler = nil
        super.tearDown()
    }

    func testMixedLibraryIncludesFoldersAndAudioButHidesTechnicalAndOtherFiles() async throws {
        LibraryURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/2/files/list_folder")
            return (200, try self.page([
                self.entry("folder", "id:series", "Series"),
                self.entry("folder", "id:hidden", ".git"),
                self.entry("file", "id:mp3", "ספר.MP3"),
                self.entry("file", "id:m4b", "Book.m4b"),
                self.entry("file", "id:m4a", "Book.m4a"),
                self.entry("file", "id:mp4", "Book.mp4"),
                self.entry("file", "id:image", "Cover.jpg"),
                self.entry("file", "id:text", "Notes.txt"),
                self.entry("file", "id:archive", "Book.zip"),
                self.entry("file", "id:cloud", "Unavailable.mp3", downloadable: false)
            ]))
        }
        let entries = try await client().listFolder("id:library")
        XCTAssertEqual(entries.first?.id, "id:series")
        XCTAssertEqual(Set(entries.compactMap(\.id)), Set(["id:series", "id:mp3", "id:m4b", "id:m4a", "id:mp4"]))
    }

    func testAllPagesUseSharedNamespaceAndStableIDsWithoutDownloadingAudio() async throws {
        var requests = [URLRequest]()
        LibraryURLProtocol.handler = { request in
            requests.append(request)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let rootData = Data(try XCTUnwrap(request.value(forHTTPHeaderField: "Dropbox-API-Path-Root")).utf8)
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: rootData) as? [String: String])
            XCTAssertEqual(root, [".tag": "namespace_id", "namespace_id": "shared-namespace"])
            if requests.count == 1 {
                let body = try self.body(of: request)
                XCTAssertEqual(body["path"] as? String, "id:library")
                XCTAssertEqual(body["recursive"] as? Bool, false)
                return (200, try self.page([self.entry("file", "id:one", "Old name.mp3")], cursor: "next-page", hasMore: true))
            }
            XCTAssertEqual(request.url?.path, "/2/files/list_folder/continue")
            XCTAssertEqual(try self.body(of: request)["cursor"] as? String, "next-page")
            return (200, try self.page([
                self.entry("file", "id:one", "New name.mp3"),
                self.entry("file", "id:two", "Another book.m4b")
            ]))
        }

        let entries = try await client(namespaceID: "shared-namespace").listFolder("id:library")
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first(where: { $0.id == "id:one" })?.name, "New name.mp3")
    }

    func testExpiredAuthorizationRequiresSignInAndDoesNotReturnPartialCatalog() async throws {
        var count = 0
        LibraryURLProtocol.handler = { _ in
            count += 1
            if count == 1 {
                return (200, try self.page([self.entry("file", "id:one", "Book.mp3")], cursor: "next", hasMore: true))
            }
            return (401, Data())
        }
        do {
            _ = try await client().listFolder("id:library")
            XCTFail("An incomplete catalog must not be presented as a successful refresh")
        } catch {
            XCTAssertEqual(error as? DropboxLibraryClient.LibraryError, .authorizationRequired)
        }
    }

    func testRepeatedCursorFailsInsteadOfLoopingForever() async throws {
        var count = 0
        LibraryURLProtocol.handler = { _ in
            count += 1
            return (200, try self.page([], cursor: "repeated", hasMore: true))
        }
        do {
            _ = try await client().listFolder("id:library")
            XCTFail("A repeated cursor must be rejected")
        } catch {
            XCTAssertEqual(error as? DropboxLibraryClient.LibraryError, .invalidCursor)
            XCTAssertEqual(count, 2)
        }
    }

    func testMalformedSecondPageFailsInsteadOfReturningFirstPageOnly() async throws {
        var count = 0
        LibraryURLProtocol.handler = { _ in
            count += 1
            if count == 1 {
                return (200, try self.page([self.entry("file", "id:one", "Book.mp3")], cursor: "next", hasMore: true))
            }
            return (200, Data("not JSON".utf8))
        }
        do {
            _ = try await client().listFolder("id:library")
            XCTFail("A malformed continuation must fail the refresh")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testMissingAuthorizationDoesNotSendRequest() async throws {
        LibraryURLProtocol.handler = { _ in
            XCTFail("No request should be sent without authorization")
            return (200, Data())
        }
        let client = DropboxLibraryClient(session: session) { "" }
        do {
            _ = try await client.listFolder("id:library")
            XCTFail("Missing authorization should fail")
        } catch {
            XCTAssertEqual(error as? DropboxLibraryClient.LibraryError, .authorizationRequired)
        }
    }

    func testArtworkListingIsOptInAndStillHidesHiddenImages() async throws {
        LibraryURLProtocol.handler = { _ in
            (200, try self.page([self.entry("file", "id:book", "Book.mp3"), self.entry("file", "id:cover", "cover.jpg"), self.entry("file", "id:hidden", ".cover.jpg")]))
        }
        let contents = try await client().listFolder("id:library", includeArtwork: true)
        XCTAssertEqual(Set(contents.compactMap(\.id)), ["id:book", "id:cover"])
        XCTAssertEqual(contents.filter(\.isLibraryItem).count, 1, "A cover must not become a downloadable audiobook")
    }

    func testArtworkRequestUsesAnImageThumbnailAndSharedNamespace() async throws {
        let image = try JSONDecoder().decode(DropboxLibraryEntry.self, from: JSONSerialization.data(withJSONObject: entry("file", "id:cover", "Cover.jpg")))
        let request = try await client(namespaceID: "shared-library").artworkRequest(for: image)
        XCTAssertEqual(request.url?.path, "/2/files/get_thumbnail_v2")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
        XCTAssertNil(request.httpBody)
        let arguments = try XCTUnwrap(request.value(forHTTPHeaderField: "Dropbox-API-Arg"))
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: [String: String]])
        XCTAssertEqual(decoded["resource"], [".tag": "path", "path": "id:cover"])
        XCTAssertEqual(decoded["mode"], [".tag": "bestfit"], "Preserve the full cover instead of cropping its title")
        XCTAssertEqual(decoded["size"], [".tag": "w1024h768"])
        let pathRoot = try XCTUnwrap(request.value(forHTTPHeaderField: "Dropbox-API-Path-Root"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(pathRoot.utf8)) as? [String: String], [".tag": "namespace_id", "namespace_id": "shared-library"])
    }

    func testArtworkRequestRejectsAudioBeforeRequestingCredentials() async throws {
        let audio = try JSONDecoder().decode(DropboxLibraryEntry.self, from: JSONSerialization.data(withJSONObject: entry("file", "id:book", "Book.mp3")))
        let client = DropboxLibraryClient { XCTFail("Artwork must not request audio or credentials for it"); return "test-token" }
        do {
            _ = try await client.artworkRequest(for: audio)
            XCTFail("Audio cannot be requested through the cover loader")
        } catch { XCTAssertEqual(error as? DropboxLibraryClient.LibraryError, .invalidResponse) }
    }

    func testGenericFolderCoverIsNotAssignedToMultipleDifferentBooks() throws {
        let contents = try [entry("file", "id:one", "One.mp3"), entry("file", "id:two", "Two.mp3"), entry("file", "id:cover", "cover.jpg")].map {
            try JSONDecoder().decode(DropboxLibraryEntry.self, from: JSONSerialization.data(withJSONObject: $0))
        }
        XCTAssertNil(BooksArtwork.cover(for: contents[0], in: contents))
        XCTAssertEqual(BooksArtwork.cover(for: contents[0], in: [contents[0], contents[2]])?.id, "id:cover")
        XCTAssertEqual(BooksArtwork.cover(for: nil, in: contents)?.id, "id:cover", "A generic image may still represent the collection")
    }

    func testBookTitlesPreserveDottedFolderNames() {
        XCTAssertEqual(BooksArtwork.title("J. R. R. Tolkien"), "J. R. R. Tolkien")
        XCTAssertEqual(BooksArtwork.title("An Author - 2024 - A Title (Mystery)"), "A Title")
        XCTAssertEqual(BooksArtwork.title("A_Title.MP3"), "A Title")
    }

    private func client(namespaceID: String? = nil) -> DropboxLibraryClient {
        DropboxLibraryClient(session: session, namespaceID: namespaceID) { "test-token" }
    }

    private func entry(_ kind: String, _ id: String, _ name: String, downloadable: Bool = true) -> [String: Any] {
        [".tag": kind, "id": id, "name": name, "is_downloadable": downloadable]
    }

    private func page(_ entries: [[String: Any]], cursor: String = "finished", hasMore: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["entries": entries, "cursor": cursor, "has_more": hasMore])
    }

    private func body(of request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else {
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            var body = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            data = body
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class LibraryURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            let handler = try XCTUnwrap(Self.handler)
            let (status, data) = try handler(request)
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
