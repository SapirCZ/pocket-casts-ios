import XCTest
@testable import podcasts
import PocketCastsDataModel

final class BooksDownloadRequestTests: XCTestCase {
    func testContentDownloadUsesBinaryContentTypeAndHeaderArgumentsWithoutAFormBody() async throws {
        let client = DropboxLibraryClient(namespaceID: "shared-library") { "test-token" }
        let book = PersonalBook(accountID: "account", fileID: "id:book", revision: "saved-revision", contentHash: String(repeating: "a", count: 64), fileName: "Book.m4b", size: 123)
        let request = try await client.downloadRequest(for: book)
        XCTAssertEqual(request.url?.absoluteString, "https://content.dropboxapi.com/2/files/download")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
        XCTAssertNil(request.httpBody, "Dropbox content-download arguments belong in headers, not in a form body")
        let arguments = try XCTUnwrap(request.value(forHTTPHeaderField: "Dropbox-API-Arg"))
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: String])
        XCTAssertEqual(decoded, ["path": "rev:saved-revision"])
        XCTAssertNil(decoded["rev"], "Dropbox rejects the deprecated separate revision argument")
        let root = try XCTUnwrap(request.value(forHTTPHeaderField: "Dropbox-API-Path-Root"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: Data(root.utf8)) as? [String: String], [".tag": "namespace_id", "namespace_id": "shared-library"])
    }
}
