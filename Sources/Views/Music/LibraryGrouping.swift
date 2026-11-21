import Foundation

// MARK: - Группы медиатеки (альбомы/артисты), вычисляемые из библиотеки.

/// Альбом: треки с одинаковым (album, artist). Трек без тега альбома
/// считается «синглом» — альбом из одного трека с его названием.
struct AlbumGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let trackIDs: [UUID]
    let coverID: UUID?
    let dateAdded: Date
    let totalDuration: TimeInterval

    var itemCount: Int { trackIDs.count }
}

struct ArtistGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let trackIDs: [UUID]
    let albumIDs: [String]
    let coverID: UUID?
}

enum LibraryGrouping {
    static func albums(from items: [MediaItem]) -> [AlbumGroup] {
        var byKey: [String: [MediaItem]] = [:]
        for item in items {
            let key = albumKey(for: item)
            byKey[key, default: []].append(item)
        }
        return byKey
            .map { key, group in
                let sorted = group.sorted { $0.dateAdded > $1.dateAdded }
                let first = sorted[0]
                return AlbumGroup(
                    id: key,
                    title: displayAlbum(for: first),
                    artist: first.displayArtist,
                    trackIDs: sorted.map(\.id),
                    coverID: (sorted.first { $0.artworkFileName != nil } ?? first).id,
                    dateAdded: sorted.map(\.dateAdded).max() ?? .now,
                    totalDuration: sorted.reduce(0) { $0 + $1.duration }
                )
            }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    static func artists(from items: [MediaItem]) -> [ArtistGroup] {
        let albums = albums(from: items)
        var byKey: [String: [MediaItem]] = [:]
        for item in items {
            let key = item.displayArtist.lowercased()
            byKey[key, default: []].append(item)
        }
        return byKey
            .map { key, group in
                let sorted = group.sorted { $0.dateAdded > $1.dateAdded }
                let first = sorted[0]
                let artistAlbums = albums.filter { $0.artist.lowercased() == key }
                return ArtistGroup(
                    id: key,
                    name: first.displayArtist,
                    trackIDs: sorted.map(\.id),
                    albumIDs: artistAlbums.map(\.id),
                    coverID: (sorted.first { $0.artworkFileName != nil } ?? first).id
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func albumKey(for item: MediaItem) -> String {
        let album = item.album?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (album?.isEmpty == false) ? album! : item.title
        return "\(name.lowercased())|\(item.displayArtist.lowercased())"
    }

    static func displayAlbum(for item: MediaItem) -> String {
        let album = item.album?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (album?.isEmpty == false) ? album! : item.title
    }
}
