import Foundation
import SwiftData

@Model
final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    /// Порядок треков хранится явно — так плейлист можно переставлять.
    var itemIDs: [UUID]

    init(id: UUID = UUID(), name: String, createdAt: Date = .now, itemIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.itemIDs = itemIDs
    }
}
