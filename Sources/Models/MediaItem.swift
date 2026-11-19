import Foundation
import SwiftData

@Model
final class MediaItem {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var storageTypeRaw: String

    /// Путь относительно Documents — не ломается при смене UUID контейнера.
    var relativePath: String?
    var bookmarkData: Data?

    var title: String
    var artist: String?
    var album: String?
    var duration: TimeInterval
    var playbackPosition: TimeInterval
    var fileSize: Int64
    var dateAdded: Date
    var artworkFileName: String?
    var isFavorite: Bool
    var playCount: Int

    init(
        id: UUID = UUID(),
        kind: MediaKind,
        storageType: MediaStorageType,
        relativePath: String? = nil,
        bookmarkData: Data? = nil,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval = 0,
        playbackPosition: TimeInterval = 0,
        fileSize: Int64 = 0,
        dateAdded: Date = .now,
        artworkFileName: String? = nil,
        isFavorite: Bool = false,
        playCount: Int = 0
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.storageTypeRaw = storageType.rawValue
        self.relativePath = relativePath
        self.bookmarkData = bookmarkData
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.playbackPosition = playbackPosition
        self.fileSize = fileSize
        self.dateAdded = dateAdded
        self.artworkFileName = artworkFileName
        self.isFavorite = isFavorite
        self.playCount = playCount
    }

    var kind: MediaKind {
        get { MediaKind(rawValue: kindRaw) ?? .audio }
        set { kindRaw = newValue.rawValue }
    }

    var storageType: MediaStorageType {
        get { MediaStorageType(rawValue: storageTypeRaw) ?? .localDocuments }
        set { storageTypeRaw = newValue.rawValue }
    }

    var displayArtist: String { artist ?? "Неизвестный исполнитель" }

    /// Восстановление позиции с небольшим откатом назад (как подкаст-плееры).
    var resumePosition: TimeInterval {
        guard playbackPosition > 0 else { return 0 }
        guard duration <= 0 || playbackPosition < duration - 5 else { return 0 }
        return max(0, playbackPosition - 2)
    }
}
