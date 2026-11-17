import Foundation

/// Device-local book identity. This record outlives its disposable UserEpisode/audio file.
public struct PersonalBook: Codable, Equatable, Identifiable {
    public let id: String
    public let accountID: String
    public let fileID: String
    public let revision: String
    public let contentHash: String
    public let fileName: String
    public let title: String
    public let size: Int64
    public var playedUpTo: Double = 0
    public var duration: Double = 0
    public var playingStatus: Int32 = PlayingStatus.notPlayed.rawValue

    public init(id: String = UUID().uuidString, accountID: String, fileID: String, revision: String, contentHash: String, fileName: String, size: Int64) {
        self.id = id
        self.accountID = accountID
        self.fileID = fileID
        self.revision = revision
        self.contentHash = contentHash
        self.fileName = fileName
        self.title = (fileName as NSString).deletingPathExtension
        self.size = size
    }
}
