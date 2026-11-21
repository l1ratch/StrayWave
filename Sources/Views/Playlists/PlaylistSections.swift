import SwiftUI
import SwiftData

// MARK: - Обложка плейлиста
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
