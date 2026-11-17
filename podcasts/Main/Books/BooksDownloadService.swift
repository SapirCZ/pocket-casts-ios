import AVFoundation
import CryptoKit
import Foundation
import PocketCastsDataModel
import PocketCastsUtils

struct DropboxDownloadMetadata: Decodable {
    let id: String
    let rev: String
    let content_hash: String
    let size: Int64
}

final class BooksDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let expectedSize: Int64
    let update: @Sendable (Double) -> Void

    init(expectedSize: Int64, update: @escaping @Sendable (Double) -> Void) {
        self.expectedSize = expectedSize
        self.update = update
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        if expected > 0 { update(min(1, Double(totalBytesWritten) / Double(expected))) }
    }
}

protocol BooksFileDownloading {
    func download(_ book: PersonalBook, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
}

extension DropboxLibraryClient: BooksFileDownloading {
    func downloadRequest(for book: PersonalBook) async throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/download")!)
        request.httpMethod = "POST"
        // Explicitly use the content-download contract; URLSession must not infer a form body.
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        // Dropbox rejects the retired separate `rev` argument; pin the revision in ReadPath.
        let argument = try JSONEncoder().encode(["path": "rev:" + book.revision])
        request.setValue(String(decoding: argument, as: UTF8.self), forHTTPHeaderField: "Dropbox-API-Arg")
        if let namespaceID {
            let root = try JSONEncoder().encode([".tag": "namespace_id", "namespace_id": namespaceID])
            request.setValue(String(decoding: root, as: UTF8.self), forHTTPHeaderField: "Dropbox-API-Path-Root")
        }
        return request
    }

    func download(_ book: PersonalBook, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let request = try await downloadRequest(for: book)
        let delegate = BooksDownloadProgress(expectedSize: book.size, update: progress)
        let (file, response) = try await session.download(for: request, delegate: delegate)
        do {
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw BooksError.downloadResponse }
            // Diagnostics deliberately contain no URL, credentials, filenames, metadata, or response body.
            let hasMetadata = http.value(forHTTPHeaderField: "Dropbox-API-Result") != nil
            FileLog.shared.addMessage("Books download HTTP status=\(http.statusCode) metadata=\(hasMetadata)", to: .console)
            guard http.statusCode != 401 else { throw BooksError.authorization }
            guard http.statusCode == 200,
                  let header = http.value(forHTTPHeaderField: "Dropbox-API-Result") else { throw BooksError.downloadResponse }
            let metadata = try JSONDecoder().decode(DropboxDownloadMetadata.self, from: Data(header.utf8))
            guard metadata.id == book.fileID, metadata.rev == book.revision,
                  metadata.size == book.size, metadata.content_hash == book.contentHash else { throw BooksError.changedFile }
            return file
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }
}

enum BooksFileValidation {
    /// Dropbox hashes 4 MiB blocks, then hashes the concatenation of the binary block hashes.
    static func contentHash(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var outer = SHA256()
        var block = SHA256()
        var blockBytes = 0
        while let data = try handle.read(upToCount: min(64 * 1024, 4 * 1024 * 1024 - blockBytes)), !data.isEmpty {
            try Task.checkCancellation()
            block.update(data: data)
            blockBytes += data.count
            if blockBytes == 4 * 1024 * 1024 {
                outer.update(data: Data(block.finalize()))
                block = SHA256()
                blockBytes = 0
            }
        }
        if blockBytes > 0 { outer.update(data: Data(block.finalize())) }
        return outer.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func validate(_ url: URL, book: PersonalBook) async throws -> Double {
        let task = Task.detached(priority: .utility) {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.size] as? NSNumber)?.int64Value == book.size,
                  try contentHash(at: url) == book.contentHash else { throw BooksError.changedFile }
            do {
                let asset = AVURLAsset(url: url)
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                let duration = try await asset.load(.duration).seconds
                guard !tracks.isEmpty, duration.isFinite, duration > 0,
                      try await asset.load(.isPlayable) else { throw BooksError.invalidAudio }
                try Task.checkCancellation()
                return duration
            } catch is CancellationError { throw CancellationError() }
            catch { throw BooksError.invalidAudio }
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    static func mediaType(fileName: String) throws -> String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "mp3": return "audio/mp3"
        case "m4b": return "audio/x-m4b"
        case "m4a": return "audio/x-m4a"
        case "mp4": return "audio/mp4"
        default: throw BooksError.invalidAudio
        }
    }
}

@MainActor
final class BooksDownloadService {
    let dataManager: DataManager
    let pathFinder: FilePathProtocol
    let enqueue: (UserEpisode) -> Void

    init(dataManager: DataManager = .sharedManager, pathFinder: FilePathProtocol = DownloadManager.shared, enqueue: @escaping (UserEpisode) -> Void = {
        PlaybackManager.shared.addToUpNext(episode: $0, ignoringQueueLimit: true, userInitiated: false)
    }) {
        self.dataManager = dataManager
        self.pathFinder = pathFinder
        self.enqueue = enqueue
    }

    func downloadAndQueue(_ book: PersonalBook, client: BooksFileDownloading, progress: @escaping @Sendable (Double) -> Void, validating: () -> Void) async throws {
        try Task.checkCancellation()
        let book = try dataManager.obtainPersonalBook(book)
        if queueDownloaded(book) { return }
        let episode = UserEpisode()
        episode.uuid = book.id
        episode.title = book.title
        episode.fileType = try BooksFileValidation.mediaType(fileName: book.fileName)
        episode.sizeInBytes = book.size
        episode.addedDate = Date()
        episode.publishedDate = Date()
        episode.uploadStatus = UploadStatus.notUploaded.rawValue
        episode.playedUpTo = book.playedUpTo
        episode.playingStatus = book.playingStatus

        let destination = URL(fileURLWithPath: pathFinder.pathForEpisode(episode))
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recovered = FileManager.default.fileExists(atPath: destination.path)
        if !recovered {
            let capacity = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
            if let capacity, capacity < book.size + 32 * 1024 * 1024 { throw BooksError.diskSpace }
        }
        let temporary: URL
        if recovered { temporary = destination }
        else {
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("BooksDownloads", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let source = try await client.download(book, progress: progress)
            temporary = staging.appendingPathComponent(UUID().uuidString).appendingPathExtension((book.fileName as NSString).pathExtension.lowercased())
            do { try FileManager.default.moveItem(at: source, to: temporary) }
            catch {
                try? FileManager.default.removeItem(at: source)
                throw error
            }
        }
        defer { if !recovered { try? FileManager.default.removeItem(at: temporary) } }
        validating()
        let duration: Double
        do { duration = try await BooksFileValidation.validate(temporary, book: book) }
        catch {
            if recovered, !(error is CancellationError) { try? FileManager.default.removeItem(at: destination) }
            throw error
        }
        try Task.checkCancellation()
        // A crash after the move is recoverable on the next selection, using the same book UUID.
        if !recovered { try FileManager.default.moveItem(at: temporary, to: destination) }
        episode.duration = duration
        episode.playedUpTo = min(book.playedUpTo, duration)
        episode.episodeStatus = DownloadStatus.downloaded.rawValue
        dataManager.save(episode: episode)
        guard let persisted = dataManager.findUserEpisode(uuid: book.id), persisted.downloaded(pathFinder: pathFinder) else { throw BooksError.persistence }
        dataManager.saveEpisode(duration: duration, episode: persisted, updateSyncFlag: false)
        enqueue(persisted)
        NotificationCenter.postOnMainThread(notification: Constants.Notifications.userEpisodeUpdated, object: book.id)
    }

    @discardableResult
    func queueDownloaded(_ book: PersonalBook) -> Bool {
        guard let episode = dataManager.findUserEpisode(uuid: book.id), episode.downloaded(pathFinder: pathFinder) else { return false }
        enqueue(episode)
        return true
    }
}
