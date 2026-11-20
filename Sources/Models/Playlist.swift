import Foundation
import SwiftData

@Model
final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    /// Порядок треков хранится явно — так плейлист можно переставлять.
    var itemIDs: [UUID]
    /// Плейлисты бывают музыкальные и видео — тип задаётся при создании.
    /// Дефолт на уровне свойства — ради чистой SwiftData-миграции.
    var kindRaw: String = MediaKind.audio.rawValue
    /// Короткое описание (видно в списках и на экране плейлиста).
    var playlistDescription: String?
    /// Пользовательская обложка; externalStorage — картинка живёт файлом,
    /// а не внутри sqlite-строки.
    @Attribute(.externalStorage) var coverImageData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        itemIDs: [UUID] = [],
        kind: MediaKind = .audio,
        playlistDescription: String? = nil,
        coverImageData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.itemIDs = itemIDs
        self.kindRaw = kind.rawValue
        self.playlistDescription = playlistDescription
        self.coverImageData = coverImageData
    }

    var kind: MediaKind {
        get { MediaKind(rawValue: kindRaw) ?? .audio }
        set { kindRaw = newValue.rawValue }
    }

    var trimmedDescription: String? {
        guard let text = playlistDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }
}
