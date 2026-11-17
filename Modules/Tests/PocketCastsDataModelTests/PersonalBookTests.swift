import XCTest
@testable import PocketCastsDataModel

final class PersonalBookTests: DataManagerTestCase {
    func testRenameAndRetryPreserveIdentityButDifferentAccountsRemainSeparate() throws {
        try runWithBothImplementations { manager, _ in
            let first = try manager.obtainPersonalBook(book(name: "Original.mp3"))
            let renamed = try manager.obtainPersonalBook(book(name: "Renamed.mp3"))
            let otherAccount = try manager.obtainPersonalBook(book(account: "other-account", name: "Original.mp3"))
            XCTAssertEqual(first.id, renamed.id)
            XCTAssertEqual(renamed.fileName, "Original.mp3", "Keep the pinned audio version and metadata")
            XCTAssertNotEqual(first.id, otherAccount.id)
            XCTAssertEqual(try manager.personalBooks().count, 2)
        }
    }

    func testRemovingUserEpisodeKeepsBookAndProgressAndPreventsCloudSync() throws {
        try runWithBothImplementations { manager, _ in
            let book = try manager.obtainPersonalBook(book(name: "Book.m4b"))
            let episode = UserEpisode()
            episode.uuid = book.id
            episode.title = book.title
            episode.addedDate = Date()
            episode.publishedDate = Date()
            episode.episodeStatus = DownloadStatus.downloaded.rawValue
            episode.uploadStatus = UploadStatus.notUploaded.rawValue
            episode.playedUpToModified = 1
            episode.titleModified = 1
            manager.save(episode: episode)
            XCTAssertNotNil(manager.findUserEpisode(uuid: book.id))
            manager.saveEpisode(playedUpTo: 123, episode: episode, updateSyncFlag: true)
            manager.saveEpisode(duration: 500, episode: episode, updateSyncFlag: false)
            manager.saveEpisode(playingStatus: .inProgress, episode: episode, updateSyncFlag: true)
            XCTAssertFalse(manager.canSyncUserEpisode(uuid: episode.uuid))
            XCTAssertFalse(manager.unsyncedUserEpisodes().contains(where: { $0.uuid == book.id }))
            manager.delete(userEpisodeUuid: episode.uuid)
            XCTAssertNil(manager.findUserEpisode(uuid: episode.uuid))
            let saved = try XCTUnwrap(manager.personalBooks().first)
            XCTAssertEqual(saved.playedUpTo, 123)
            XCTAssertEqual(saved.duration, 500)
            XCTAssertEqual(saved.playingStatus, PlayingStatus.inProgress.rawValue)
            XCTAssertFalse(manager.canSyncUserEpisode(uuid: episode.uuid), "Privacy identity must survive audio deletion")
            XCTAssertTrue(manager.canSyncUserEpisode(uuid: "ordinary-user-file"))
        }
    }

    func testRemoteQueueCleanupPreservesDeviceLocalBooks() throws {
        try runWithBothImplementations { manager, _ in
            let book = try manager.obtainPersonalBook(book(name: "Book.mp3"))
            let episode = UserEpisode()
            episode.uuid = book.id
            episode.title = book.title
            episode.addedDate = Date()
            episode.episodeStatus = DownloadStatus.downloaded.rawValue
            manager.save(episode: episode)
            let item = PlaylistEpisode()
            item.episodeUuid = book.id
            item.podcastUuid = DataConstants.userEpisodeFakePodcastId
            manager.save(playlistEpisode: item)
            XCTAssertTrue(manager.hasPersonalBooksInUpNext())
            manager.deleteAllUpNextEpisodesNotIn(uuids: [])
            XCTAssertTrue(manager.hasPersonalBooksInUpNext())
            XCTAssertTrue(manager.allUpNextEpisodes().contains(where: { $0.uuid == book.id }))
        }
    }

    private func book(account: String = "account", name: String) -> PersonalBook {
        PersonalBook(accountID: account, fileID: "id:source", revision: "revision", contentHash: String(repeating: "a", count: 64), fileName: name, size: 123)
    }
}
