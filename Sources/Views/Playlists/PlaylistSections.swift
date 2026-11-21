import SwiftUI
import SwiftData

// MARK: - Секция плейлистов в «Музыке» (в стиле Apple Music)

struct MusicPlaylistsSection: View {
    @Query private var playlists: [Playlist]
    @Query private var allItems: [MediaItem]

    private var audioPlaylists: [Playlist] {
        playlists
            .filter { $0.kind == .audio }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        if !audioPlaylists.isEmpty {
            Section("Плейлисты") {
                ForEach(audioPlaylists) { playlist in
                    NavigationLink(value: playlist.id) {
                        HStack(spacing: 12) {
                            PlaylistArtwork(playlist: playlist, items: items(of: playlist))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.name)
                                Text(subtitle(for: playlist))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .contextMenu { PlaylistDeleteButton(playlist: playlist) }
                }
            }
        }
    }

    private func subtitle(for playlist: Playlist) -> String {
        let count = "\(playlist.itemIDs.count) треков"
        if let description = playlist.trimmedDescription {
            return "\(count) · \(description)"
        }
        return count
    }

    private func items(of playlist: Playlist) -> [MediaItem] {
        let byID = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return playlist.itemIDs.compactMap { byID[$0] }
    }
}

/// Обложка плейлиста: пользовательская картинка → превью первого трека → градиент.
struct PlaylistArtwork: View {
    let playlist: Playlist
    let items: [MediaItem]
    var size: CGFloat = 48
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let data = playlist.coverImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let first = items.first {
                ArtworkImage(item: first, size: size, cornerRadius: cornerRadius)
            } else {
                ZStack {
                    LinearGradient(
                        colors: playlist.kind == .video
                            ? [.indigo.opacity(0.6), .purple.opacity(0.4)]
                            : [.blue.opacity(0.5), .teal.opacity(0.3)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Image(systemName: playlist.kind == .video ? "film.fill" : "music.note.list")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Полоса плейлистов в «Видео»

struct VideoPlaylistsStrip: View {
    @Environment(MediaPlayerEngine.self) private var engine
    @Query private var playlists: [Playlist]
    @Query private var allItems: [MediaItem]

    private var videoPlaylists: [Playlist] {
        playlists
            .filter { $0.kind == .video }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        if !videoPlaylists.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Плейлисты")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(videoPlaylists) { playlist in
                            NavigationLink(value: playlist.id) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ZStack {
                                        PlaylistArtwork(
                                            playlist: playlist,
                                            items: items(of: playlist),
                                            size: 140,
                                            cornerRadius: 10
                                        )
                                    }
                                    .frame(width: 140, height: 79)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    Text(playlist.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .frame(width: 140, alignment: .leading)
                                    Text("\(playlist.itemIDs.count) видео")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 140, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu { PlaylistDeleteButton(playlist: playlist) }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func items(of playlist: Playlist) -> [MediaItem] {
        let byID = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return playlist.itemIDs.compactMap { byID[$0] }
    }
}

// MARK: - Меню «В плейлист» для строки/ячейки

struct AddToPlaylistMenu: View {
    @Query private var playlists: [Playlist]
    let item: MediaItem

    var body: some View {
        let matching = playlists.filter { $0.kind == item.kind }
        if matching.isEmpty {
            Text("Плейлистов этого типа пока нет")
        } else {
            Menu("В плейлист") {
                ForEach(matching) { playlist in
                    Button(playlist.name) {
                        if !playlist.itemIDs.contains(item.id) {
                            playlist.itemIDs.append(item.id)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Удаление плейлиста

/// Красная кнопка удаления для contextMenu/меню тулбара. Сами файлы не
/// трогаются — удаляется только список.
struct PlaylistDeleteButton: View {
    @Environment(\.modelContext) private var context
    let playlist: Playlist
    var onDeleted: () -> Void = {}

    var body: some View {
        Button(role: .destructive) {
            context.delete(playlist)
            try? context.save()
            DebugLog.shared.add("🗑 плейлист «\(playlist.name)» удалён")
            onDeleted()
        } label: {
            Label("Удалить плейлист", systemImage: "trash")
        }
    }
}
