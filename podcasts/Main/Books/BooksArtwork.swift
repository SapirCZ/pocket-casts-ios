import AVFoundation
import CryptoKit
import ImageIO
import UIKit

enum BooksArtwork {
    static func title(_ name: String) -> String {
        let pathExtension = (name as NSString).pathExtension.lowercased()
        let plain = ["mp3", "mp4", "m4b", "m4a"].contains(pathExtension) ? (name as NSString).deletingPathExtension : name
        // A common library folder convention is "Author - Year - Title (Genre)".
        let parts = plain.components(separatedBy: " - ")
        if parts.count >= 3, parts[1].count == 4, Int(parts[1]) != nil {
            return parts.dropFirst(2).joined(separator: " - ")
                .replacingOccurrences(of: #"\s+\([^)]*\)$"#, with: "", options: .regularExpression)
        }
        return plain.replacingOccurrences(of: "_", with: " ")
    }

    static func cover(for entry: DropboxLibraryEntry?, in contents: [DropboxLibraryEntry]) -> DropboxLibraryEntry? {
        let images = contents.filter(\.isArtwork).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let entry {
            let stem = normalized(entry.name)
            if let match = images.first(where: { normalized($0.name) == stem || normalized($0.name) == stem + "cover" }) { return match }
            // A shared folder image must not be assigned to unrelated books in a series.
            guard contents.filter({ $0.kind == .file && $0.isLibraryItem }).count == 1 else { return nil }
        }
        for name in ["cover", "front", "folder", "artwork"] {
            if let image = images.first(where: { normalized($0.name) == name }) { return image }
        }
        return images.count == 1 ? images.first : nil
    }

    private static func normalized(_ name: String) -> String {
        (name as NSString).deletingPathExtension.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}

extension DropboxLibraryClient {
    func artworkRequest(for image: DropboxLibraryEntry) async throws -> URLRequest {
        guard image.isArtwork, let id = image.id else { throw LibraryError.invalidResponse }
        var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/get_thumbnail_v2")!)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        let arguments = ["resource": [".tag": "path", "path": id], "format": [".tag": "jpeg"], "size": [".tag": "w1024h768"], "mode": [".tag": "bestfit"]]
        let data = try JSONEncoder().encode(arguments)
        request.setValue(String(decoding: data, as: UTF8.self), forHTTPHeaderField: "Dropbox-API-Arg")
        if let namespaceID {
            let root = try JSONEncoder().encode([".tag": "namespace_id", "namespace_id": namespaceID])
            request.setValue(String(decoding: root, as: UTF8.self), forHTTPHeaderField: "Dropbox-API-Path-Root")
        }
        return request
    }

    func artworkData(for image: DropboxLibraryEntry) async throws -> Data {
        let request = try await artworkRequest(for: image)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2 * 1024 * 1024 else { throw LibraryError.invalidResponse }
        return data
    }
}

/// Device-local thumbnails. Audio is never downloaded just to obtain a cover.
@MainActor
final class BooksArtworkCache {
    static let shared = BooksArtworkCache()
    private let memory = NSCache<NSString, UIImage>()
    private var inFlight = [String: Task<UIImage?, Never>]()
    private var misses = [String: Date]()
    private let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("BooksArtwork", isDirectory: true)

    init() { memory.countLimit = 96 }

    func image(key: String, load: @escaping @MainActor () async throws -> Data?) async -> UIImage? {
        if let image = memory.object(forKey: key as NSString) { return image }
        let path = directory.appendingPathComponent(SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()).appendingPathExtension("jpg")
        if let data = try? Data(contentsOf: path), let image = UIImage(data: data) {
            memory.setObject(image, forKey: key as NSString)
            return image
        }
        if let task = inFlight[key] { return await task.value }
        if let date = misses[key], Date().timeIntervalSince(date) < 60 { return nil }
        let task = Task<UIImage?, Never> {
            guard let data = try? await load(), data.count <= 6 * 1024 * 1024,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 768, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
            let image = UIImage(cgImage: cgImage)
            if let jpeg = image.jpegData(compressionQuality: 0.9) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? jpeg.write(to: path, options: .atomic)
            }
            memory.setObject(image, forKey: key as NSString)
            return image
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if image == nil { misses[key] = Date() }
        return image
    }

    func embeddedArtwork(at url: URL, key: String) async -> UIImage? {
        await image(key: key) {
            let metadata = try await AVURLAsset(url: url).load(.commonMetadata)
            for item in metadata where item.commonKey == .commonKeyArtwork {
                if let data = try await item.load(.dataValue) { return data }
            }
            return nil
        }
    }
}
