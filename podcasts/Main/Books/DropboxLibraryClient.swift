import Foundation
import PocketCastsUtils

/// Remote metadata only. Listing a library must never download its audio.
struct DropboxLibraryEntry: Decodable, Equatable, Identifiable {
    enum Kind: String, Decodable {
        case file, folder, deleted
    }

    let kind: Kind
    let name: String
    let id: String?
    let pathDisplay: String?
    let size: UInt64?
    let revision: String?
    let contentHash: String?
    let isDownloadable: Bool?

    enum CodingKeys: String, CodingKey {
        case kind = ".tag"
        case name, id, size
        case pathDisplay = "path_display"
        case revision = "rev"
        case contentHash = "content_hash"
        case isDownloadable = "is_downloadable"
    }

    /// MP4 is a candidate container; the download/import step must validate its audio track.
    var isLibraryItem: Bool {
        guard !name.hasPrefix("."), let id, !id.isEmpty else { return false }
        switch kind {
        case .folder:
            return true
        case .file:
            let fileExtension = (name as NSString).pathExtension.lowercased()
            return isDownloadable != false && ["mp3", "m4a", "m4b", "mp4"].contains(fileExtension)
        case .deleted:
            return false
        }
    }

    var isArtwork: Bool {
        guard kind == .file, !name.hasPrefix("."), let id, !id.isEmpty, isDownloadable != false else { return false }
        return ["jpg", "jpeg", "png", "webp", "tif", "tiff"].contains((name as NSString).pathExtension.lowercased())
    }
}

/// Read-only Dropbox API boundary. OAuth and durable book records are separate concerns.
/// A mounted shared library can supply its namespace ID; IDs remain the browsing keys.
struct DropboxLibraryClient {
    enum LibraryError: LocalizedError, Equatable {
        case authorizationRequired
        case requestFailed(statusCode: Int)
        case invalidResponse
        case invalidCursor

        var errorDescription: String? {
            self == .authorizationRequired ? L10n.booksErrorAuthorization : L10n.booksErrorResponse
        }
    }

    let session: URLSession
    let namespaceID: String?
    let accessToken: () async throws -> String

    init(session: URLSession = .shared, namespaceID: String? = nil, accessToken: @escaping () async throws -> String) {
        self.session = session
        self.namespaceID = namespaceID
        self.accessToken = accessToken
    }

    /// Lists direct children and all response pages. Never returns a partial catalog on failure.
    /// Pass a Dropbox folder ID or a path relative to the configured namespace.
    func listFolder(_ path: String, includeArtwork: Bool = false) async throws -> [DropboxLibraryEntry] {
        var page = try await request("list_folder", body: ListRequest(path: path))
        var entriesByID = [String: DropboxLibraryEntry]()
        var seenCursors = Set<String>()

        while true {
            try Task.checkCancellation()
            for entry in page.entries {
                guard let id = entry.id else { continue }
                if entry.isLibraryItem || (includeArtwork && entry.isArtwork) {
                    entriesByID[id] = entry
                } else {
                    entriesByID.removeValue(forKey: id)
                }
            }
            guard page.hasMore else { break }
            guard !page.cursor.isEmpty, seenCursors.insert(page.cursor).inserted else {
                throw LibraryError.invalidCursor
            }
            page = try await request("list_folder/continue", body: ContinueRequest(cursor: page.cursor))
        }

        return entriesByID.values.sorted {
            if $0.kind != $1.kind { return $0.kind == .folder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func request<Body: Encodable>(_ route: String, body: Body) async throws -> ListResponse {
        let token = try await accessToken()
        guard !token.isEmpty else { throw LibraryError.authorizationRequired }
        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/\(route)")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let namespaceID {
            let root = [".tag": "namespace_id", "namespace_id": namespaceID]
            let data = try JSONEncoder().encode(root)
            request.setValue(String(decoding: data, as: UTF8.self), forHTTPHeaderField: "Dropbox-API-Path-Root")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw LibraryError.invalidResponse }
        guard response.statusCode != 401 else { throw LibraryError.authorizationRequired }
        guard response.statusCode == 200 else { throw LibraryError.requestFailed(statusCode: response.statusCode) }
        return try JSONDecoder().decode(ListResponse.self, from: data)
    }

    private struct ListRequest: Encodable {
        let path: String
        let recursive = false
        let include_deleted = false
        let include_non_downloadable_files = false
    }

    private struct ContinueRequest: Encodable {
        let cursor: String
    }

    private struct ListResponse: Decodable {
        let entries: [DropboxLibraryEntry]
        let cursor: String
        let hasMore: Bool

        enum CodingKeys: String, CodingKey {
            case entries, cursor
            case hasMore = "has_more"
        }
    }
}
