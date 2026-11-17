import AVFoundation
import GRDB
import XCTest
@testable import podcasts
@testable import PocketCastsDataModel

final class BooksImportTests: XCTestCase {
    func testDropboxHashVectorsIncludingEmptyAndBlockBoundary() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let vectors: [(Data, String)] = [
            (Data(), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            (Data("abc".utf8), "4f8b42c22dd3729b519ba6f68d2da7cc5b2d606d05daed5ad5128cc03e6c6358"),
            (Data(repeating: 0, count: 4194304), "c7e946d101855255d919ef0c70718633adf77d3dfb3adeeecf5d0cb4e951be58"),
            (Data(repeating: 0, count: 4194304) + Data("abc".utf8), "3fa6db8310a97daafad66b46d1d89070c4fe821f88b40cb9a06fa9aca84e30ce")
        ]
        for (data, hash) in vectors {
            try data.write(to: url)
            XCTAssertEqual(try BooksFileValidation.contentHash(at: url), hash)
        }
    }

    @MainActor
    func testValidAudioIsStoredAndQueuedAndRepeatedSelectionDoesNotDownloadAgain() async throws {
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "sleep-timer-restarted-sound", withExtension: "mp3"))
        try await verifySuccessfulImport(fixture: fixture, fileName: "Book.mp3")
    }

    @MainActor
    func testM4BContainerIsValidatedAndKeepsItsExtension() async throws {
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "sleep-timer-restarted-sound", withExtension: "mp3"))
        let converted = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: converted) }
        let exporter = try XCTUnwrap(AVAssetExportSession(asset: AVURLAsset(url: fixture), presetName: AVAssetExportPresetAppleM4A))
        exporter.outputURL = converted
        exporter.outputFileType = .m4a
        await withCheckedContinuation { continuation in exporter.exportAsynchronously { continuation.resume() } }
        XCTAssertEqual(exporter.status, .completed)
        try await verifySuccessfulImport(fixture: converted, fileName: "Book.m4b")
    }

    @MainActor
    func testNetworkFailureAndCorruptAudioNeverCreateEpisodeOrQueueEntry() async throws {
        let context = try context()
        defer { context.close() }
        var queued = [String]()
        let service = BooksDownloadService(dataManager: context.manager, pathFinder: context.paths) { queued.append($0.uuid) }
        let invalid = context.directory.appendingPathComponent("invalid.mp3")
        try Data("not audio".utf8).write(to: invalid)
        let book = try book(fixture: invalid, name: "Book.mp3")
        for client in [StubBookDownload(fixture: invalid, fail: true), StubBookDownload(fixture: invalid)] {
            do {
                try await service.downloadAndQueue(book, client: client, progress: { _ in }, validating: {})
                XCTFail("An invalid or incomplete download must fail")
            } catch {}
            XCTAssertNil(context.manager.findUserEpisode(uuid: book.id))
            XCTAssertTrue(queued.isEmpty)
        }
        XCTAssertEqual(try context.manager.personalBooks().count, 1, "Keep a stable identity for retry")
    }

    @MainActor
    func testModifiedBytesNeverEnterQueueAndRetryUsesSameBookIdentity() async throws {
        let fixture = try XCTUnwrap(Bundle.main.url(forResource: "sleep-timer-restarted-sound", withExtension: "mp3"))
        let context = try context()
        defer { context.close() }
        var queued = [String]()
        let service = BooksDownloadService(dataManager: context.manager, pathFinder: context.paths) { queued.append($0.uuid) }
        let book = try book(fixture: fixture, name: "Book.mp3")
        var bytes = try Data(contentsOf: fixture)
        bytes[0] ^= 1
        let modified = context.directory.appendingPathComponent("modified.mp3")
        try bytes.write(to: modified)
        do {
            try await service.downloadAndQueue(book, client: StubBookDownload(fixture: modified), progress: { _ in }, validating: {})
            XCTFail("A checksum mismatch must fail before import")
        } catch { XCTAssertEqual(error as? BooksError, .changedFile) }
        XCTAssertNil(context.manager.findUserEpisode(uuid: book.id))
        XCTAssertTrue(queued.isEmpty)
        try await service.downloadAndQueue(book, client: StubBookDownload(fixture: fixture), progress: { _ in }, validating: {})
        XCTAssertEqual(queued, [book.id])
        XCTAssertEqual(try context.manager.personalBooks().count, 1)
    }

    @MainActor
    private func verifySuccessfulImport(fixture: URL, fileName: String) async throws {
        let context = try context()
        defer { context.close() }
        var queued = [String]()
        let service = BooksDownloadService(dataManager: context.manager, pathFinder: context.paths) { queued.append($0.uuid) }
        let client = StubBookDownload(fixture: fixture)
        let book = try book(fixture: fixture, name: fileName)
        try await service.downloadAndQueue(book, client: client, progress: { _ in }, validating: {})
        let episode = try XCTUnwrap(context.manager.findUserEpisode(uuid: book.id))
        XCTAssertTrue(episode.downloaded(pathFinder: context.paths))
        XCTAssertGreaterThan(episode.duration, 0)
        XCTAssertEqual(URL(fileURLWithPath: context.paths.pathForEpisode(episode)).pathExtension, (fileName as NSString).pathExtension)
        XCTAssertFalse(context.manager.canSyncUserEpisode(uuid: book.id))
        XCTAssertEqual(episode.uploadStatus, UploadStatus.notUploaded.rawValue)
        XCTAssertEqual(queued, [book.id])
        try await service.downloadAndQueue(book, client: client, progress: { _ in }, validating: {})
        XCTAssertEqual(client.calls, 1)
        XCTAssertEqual(try context.manager.personalBooks().count, 1)
        XCTAssertEqual(queued, [book.id, book.id], "PlaybackManager deduplicates queue insertions; importer reuses the same UUID")
        let cancelled = Task { @MainActor in
            try await service.downloadAndQueue(book, client: client, progress: { _ in }, validating: {})
        }
        cancelled.cancel()
        do {
            try await cancelled.value
            XCTFail("Cancellation before selection must not enqueue the existing local copy")
        } catch is CancellationError {}
        XCTAssertEqual(queued.count, 2)
    }

    private func book(fixture: URL, name: String) throws -> PersonalBook {
        let size = try fixture.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        return PersonalBook(accountID: "account", fileID: "id:file", revision: "revision", contentHash: try BooksFileValidation.contentHash(at: fixture), fileName: name, size: Int64(size))
    }

    private func context() throws -> BookTestContext {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: directory.appendingPathComponent("test.sqlite").path)
        return BookTestContext(directory: directory, pool: pool, manager: DataManager(dbQueue: GRDBQueue(dbPool: pool)), paths: BookTestPaths(directory: directory))
    }
}

private struct BookTestContext {
    let directory: URL
    let pool: DatabasePool
    let manager: DataManager
    let paths: BookTestPaths

    func close() {
        try? pool.close()
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class BookTestPaths: NSObject, FilePathProtocol {
    let directory: URL
    init(directory: URL) { self.directory = directory }
    func pathForEpisode(_ episode: BaseEpisode) -> String {
        directory.appendingPathComponent(episode.uuid + FileTypeUtil.fileExtension(forType: episode.fileType)).path
    }
    func tempPathForEpisode(_ episode: BaseEpisode) -> String { pathForEpisode(episode) + ".tmp" }
    func streamingBufferPathForEpisode(_ episode: BaseEpisode) -> String { pathForEpisode(episode) + ".stream" }
}

private final class StubBookDownload: BooksFileDownloading {
    let fixture: URL
    let fail: Bool
    var calls = 0
    init(fixture: URL, fail: Bool = false) { self.fixture = fixture; self.fail = fail }

    func download(_ book: PersonalBook, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        calls += 1
        if fail { throw URLError(.networkConnectionLost) }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: fixture, to: copy)
        progress(1)
        return copy
    }
}
