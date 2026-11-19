import Foundation
import AppIntents
import SwiftData

struct MediaItemEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Медиафайл")
    static let defaultQuery = MediaItemQuery()

    let id: UUID
    let title: String
    let artist: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: artist.map { "\($0)" } ?? "")
    }
}

struct MediaItemQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [MediaItemEntity] {
        identifiers.compactMap { id in
            AppEnvironment.shared.mediaItem(id: id).map {
                MediaItemEntity(id: $0.id, title: $0.title, artist: $0.artist)
            }
        }
    }

    @MainActor
    func entities(matching string: String) async throws -> [MediaItemEntity] {
        AppEnvironment.shared.allMediaItems()
            .filter {
                $0.title.localizedCaseInsensitiveContains(string)
                    || ($0.artist?.localizedCaseInsensitiveContains(string) ?? false)
            }
            .map { MediaItemEntity(id: $0.id, title: $0.title, artist: $0.artist) }
    }

    @MainActor
    func suggestedEntities() async throws -> [MediaItemEntity] {
        AppEnvironment.shared.allMediaItems()
            .sorted { $0.dateAdded > $1.dateAdded }
            .prefix(20)
            .map { MediaItemEntity(id: $0.id, title: $0.title, artist: $0.artist) }
    }
}

struct PlaylistEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Плейлист")
    static let defaultQuery = PlaylistQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct PlaylistQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PlaylistEntity] {
        identifiers.compactMap { id in
            AppEnvironment.shared.allPlaylists()
                .first { $0.id == id }
                .map { PlaylistEntity(id: $0.id, name: $0.name) }
        }
    }

    @MainActor
    func entities(matching string: String) async throws -> [PlaylistEntity] {
        AppEnvironment.shared.allPlaylists()
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map { PlaylistEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [PlaylistEntity] {
        AppEnvironment.shared.allPlaylists().map { PlaylistEntity(id: $0.id, name: $0.name) }
    }
}
