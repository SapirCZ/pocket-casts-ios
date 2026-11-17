import Foundation

public extension DataManager {
    /// Unique source identity prevents duplicate imports after a rename, relaunch, or retry.
    func obtainPersonalBook(_ proposed: PersonalBook) throws -> PersonalBook {
        let json = String(decoding: try JSONEncoder().encode(proposed), as: UTF8.self)
        var result: Result<PersonalBook, Error> = .failure(PersonalBookError.persistenceFailed)
        dbQueue.inTransaction { db, rollback in
            do {
                try db.executeUpdate("INSERT OR IGNORE INTO PersonalBook (uuid, accountID, fileID, metadata) VALUES (?, ?, ?, ?)", values: [proposed.id, proposed.accountID, proposed.fileID, json])
                let rows = try db.executeQuery("SELECT * FROM PersonalBook WHERE accountID = ? AND fileID = ?", values: [proposed.accountID, proposed.fileID])
                guard rows.next() else { throw PersonalBookError.persistenceFailed }
                result = .success(try Self.readPersonalBook(rows))
            } catch {
                rollback.pointee = true
                result = .failure(error)
            }
        }
        let book = try result.get()
        // PCDBQueue reports transaction/commit errors through its logger. Verify durable insertion.
        var verified: Result<PersonalBook, Error> = .failure(PersonalBookError.persistenceFailed)
        dbQueue.read { db in
            verified = Result {
                let rows = try db.executeQuery("SELECT * FROM PersonalBook WHERE uuid = ?", values: [book.id])
                guard rows.next() else { throw PersonalBookError.persistenceFailed }
                return try Self.readPersonalBook(rows)
            }
        }
        return try verified.get()
    }

    func personalBooks() throws -> [PersonalBook] {
        var result: Result<[PersonalBook], Error> = .failure(PersonalBookError.persistenceFailed)
        dbQueue.read { db in
            result = Result {
                let rows = try db.executeQuery("SELECT * FROM PersonalBook ORDER BY rowid DESC", values: nil)
                var books = [PersonalBook]()
                while rows.next() { books.append(try Self.readPersonalBook(rows)) }
                return books
            }
        }
        return try result.get()
    }

    /// Fail closed at every Pocket Casts cloud boundary, even when the database cannot be read.
    func canSyncUserEpisode(uuid: String) -> Bool {
        var allowed = false
        dbQueue.read { db in
            guard let rows = try? db.executeQuery("SELECT count(*) AS count FROM PersonalBook WHERE uuid = ?", values: [uuid]), rows.next() else { return }
            allowed = rows.int(forColumn: "count") == 0
        }
        return allowed
    }

    func hasPersonalBooksInUpNext() -> Bool {
        var containsBooks = true
        dbQueue.read { db in
            guard let rows = try? db.executeQuery("SELECT count(*) AS count FROM PersonalBook JOIN SJPlaylistEpisode ON PersonalBook.uuid = SJPlaylistEpisode.episodeUuid WHERE SJPlaylistEpisode.playlist_id = 1", values: nil), rows.next() else { return }
            containsBooks = rows.int(forColumn: "count") > 0
        }
        return containsBooks
    }

    enum PersonalBookError: Error {
        case persistenceFailed
    }

    private static func readPersonalBook(_ row: PCDBResultSet) throws -> PersonalBook {
        guard let json = row.string(forColumn: "metadata") else { throw PersonalBookError.persistenceFailed }
        var book = try JSONDecoder().decode(PersonalBook.self, from: Data(json.utf8))
        book.playedUpTo = row.double(forColumn: "playedUpTo")
        book.duration = row.double(forColumn: "duration")
        book.playingStatus = row.int(forColumn: "playingStatus")
        return book
    }
}
