import Foundation
import PocketCastsUtils

struct BooksConfiguration: Decodable {
    let clientID: String
    let namespaceID: String
    let folderID: String

    var callbackScheme: String { "db-" + clientID }
    var redirectURI: String { callbackScheme + "://oauth" }

    static func load() -> BooksConfiguration? {
        guard let url = Bundle.main.url(forResource: "BooksLocalConfiguration", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(Self.self, from: data),
              !config.clientID.isEmpty, !config.namespaceID.isEmpty, config.folderID.hasPrefix("id:") else { return nil }
        return config
    }
}

enum BooksError: LocalizedError, Equatable {
    case configuration, authorization, invalidResponse, downloadResponse, changedFile, invalidAudio, diskSpace, persistence

    var errorDescription: String? {
        switch self {
        case .configuration: return L10n.booksConnectionPending
        case .authorization: return L10n.booksErrorAuthorization
        case .invalidResponse: return L10n.booksErrorResponse
        case .downloadResponse: return L10n.booksErrorDownload
        case .changedFile: return L10n.booksErrorChanged
        case .invalidAudio: return L10n.booksErrorAudio
        case .diskSpace: return L10n.booksErrorDiskSpace
        case .persistence: return L10n.booksErrorPersistence
        }
    }
}
