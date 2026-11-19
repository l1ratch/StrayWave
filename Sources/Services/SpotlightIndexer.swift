import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import SwiftData

/// Индексация библиотеки в системном Spotlight.
@MainActor
final class SpotlightIndexer {
    private let index = CSSearchableIndex.default()

    func reindex(items: [MediaItem]) {
        let searchable = items.map(Self.searchableItem(for:))
        index.indexSearchableItems(searchable) { _ in }
    }

    func remove(id: UUID) {
        index.deleteSearchableItems(withIdentifiers: [id.uuidString]) { _ in }
    }

    private static func searchableItem(for item: MediaItem) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: item.kind == .video ? .movie : .audio)
        attributes.title = item.title
        var descriptionParts: [String] = [item.displayArtist]
        if let album = item.album { descriptionParts.append(album) }
        descriptionParts.append(item.kind == .video ? "Видео" : "Аудио")
        attributes.contentDescription = descriptionParts.joined(separator: " · ")
        if let fileName = item.artworkFileName {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            attributes.thumbnailURL = caches
                .appendingPathComponent("Artwork", isDirectory: true)
                .appendingPathComponent(fileName)
        }
        attributes.duration = item.duration as NSNumber
        return CSSearchableItem(
            uniqueIdentifier: item.id.uuidString,
            domainIdentifier: "library",
            attributeSet: attributes
        )
    }
}
