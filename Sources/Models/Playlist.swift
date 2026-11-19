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
    /// Дефолт на уровне свойства — чтобы SwiftData легаси-мигрировала
    /// существующие хранилища без создания новой версии схемы.
    var kindRaw: String = MediaKind.audio.rawValue

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        itemIDs: [UUID] = [],
        kind: MediaKind = .audio
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.itemIDs = itemIDs
        self.kindRaw = kind.rawValue
    }

    var kind: MediaKind {
        get { MediaKind(rawValue: kindRaw) ?? .audio }
        set { kindRaw = newValue.rawValue }
    }
}
