import Combine
import Foundation
import PocketCastsDataModel
import PocketCastsUtils

@MainActor
final class BooksLibraryModel: ObservableObject {
    struct Folder {
        let id: String
        let title: String
    }

    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var loading = false
    @Published private(set) var entries = [DropboxLibraryEntry]()
    @Published private(set) var downloads = [PersonalBook]()
    @Published private(set) var folders = [Folder]()
    @Published private(set) var downloadingName: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var validating = false
    @Published private(set) var addedTitle: String?
    @Published var errorMessage: String?

    let configuration: BooksConfiguration?
    let presenter: BooksAuthenticationPresenter
    private let oauth: DropboxOAuth?
    private let downloadService: BooksDownloadService
    private var downloadTask: Task<Void, Never>?
    private var listingGeneration = 0

    init(configuration: BooksConfiguration? = BooksConfiguration.load(), presenter: BooksAuthenticationPresenter, downloadService: BooksDownloadService? = nil) {
        self.configuration = configuration
        self.presenter = presenter
        self.downloadService = downloadService ?? BooksDownloadService()
        oauth = configuration.map { DropboxOAuth(configuration: $0) }
        if let configuration { folders = [Folder(id: configuration.folderID, title: L10n.booksLibraryTitle)] }
    }

    func start() async {
        refreshDownloads()
        do { connected = try await oauth?.isConnected() ?? false }
        catch { errorMessage = BooksError.authorization.localizedDescription }
        if connected, entries.isEmpty { await refresh() }
    }

    func connect() async {
        guard let configuration, let oauth, !connecting else { return }
        connecting = true
        defer { connecting = false }
        do {
            let attempt = try DropboxOAuthAttempt(configuration: configuration)
            let callback = try await presenter.authorize(attempt)
            try await oauth.connect(attempt: attempt, callback: callback)
            connected = true
            await refresh()
        } catch is CancellationError {
            // Cancelling sign-in leaves both the catalog and local downloads unchanged.
        } catch { report(error) }
    }

    func disconnect() async {
        guard let oauth else { return }
        downloadTask?.cancel()
        do {
            try await oauth.disconnect()
            listingGeneration += 1
            connected = false
            entries = []
            if let configuration { folders = [Folder(id: configuration.folderID, title: L10n.booksLibraryTitle)] }
        } catch { report(error) }
    }

    func open(_ folder: DropboxLibraryEntry) async {
        guard folder.kind == .folder, let id = folder.id else { return }
        folders.append(Folder(id: id, title: folder.name))
        await refresh()
    }

    func back() async {
        guard folders.count > 1 else { return }
        folders.removeLast()
        await refresh()
    }

    func refresh() async {
        refreshDownloads()
        guard connected, let client = client(), let folder = folders.last else { return }
        listingGeneration += 1
        let generation = listingGeneration
        loading = true
        entries = []
        defer { if generation == listingGeneration { loading = false } }
        do {
            let listed = try await client.listFolder(folder.id)
            try Task.checkCancellation()
            if generation == listingGeneration { entries = listed }
        } catch is CancellationError {
        } catch {
            if generation == listingGeneration { report(error) }
        }
    }

    func select(_ entry: DropboxLibraryEntry) {
        guard downloadTask == nil, entry.kind == .file, let client = client(), let oauth else { return }
        downloadingName = entry.name
        progress = 0
        validating = false
        addedTitle = nil
        downloadTask = Task {
            defer {
                downloadTask = nil
                downloadingName = nil
                validating = false
                refreshDownloads()
            }
            do {
                guard entry.isLibraryItem, let id = entry.id, let revision = entry.revision,
                      let hash = entry.contentHash, hash.count == 64,
                      let size = entry.size, size > 0, size <= UInt64(Int64.max) else { throw BooksError.invalidResponse }
                let account = try await oauth.accountID()
                let proposed = PersonalBook(accountID: account, fileID: id, revision: revision, contentHash: hash, fileName: entry.name, size: Int64(size))
                let book = try downloadService.dataManager.obtainPersonalBook(proposed)
                try await downloadService.downloadAndQueue(book, client: client, progress: { [weak self] value in
                    Task { @MainActor in
                        if self?.downloadingName == entry.name { self?.progress = value }
                    }
                }, validating: { validating = true })
                addedTitle = book.title
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch { report(error) }
        }
    }

    func cancelDownload() { downloadTask?.cancel() }

    func queue(_ book: PersonalBook) {
        if downloadService.queueDownloaded(book) { addedTitle = book.title }
        else { refreshDownloads() }
    }

    private func refreshDownloads() {
        do {
            downloads = try downloadService.dataManager.personalBooks().filter { book in
                downloadService.dataManager.findUserEpisode(uuid: book.id)?.downloaded(pathFinder: downloadService.pathFinder) == true
            }
        } catch { errorMessage = BooksError.persistence.localizedDescription }
    }

    private func client() -> DropboxLibraryClient? {
        guard let configuration, let oauth else { return nil }
        return DropboxLibraryClient(namespaceID: configuration.namespaceID) { try await oauth.accessToken() }
    }

    private func report(_ error: Error) {
        if (error as? BooksError) == .authorization || (error as? DropboxLibraryClient.LibraryError) == .authorizationRequired {
            connected = false
            entries = []
        }
        errorMessage = error.localizedDescription
    }
}
