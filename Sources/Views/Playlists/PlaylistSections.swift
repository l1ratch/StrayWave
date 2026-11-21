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

// MARK: - Закрепление плейлиста

struct PlaylistPinButton: View {
    @Environment(\.modelContext) private var context
    let playlist: Playlist

    var body: some View {
        Button {
            playlist.isPinned.toggle()
            try? context.save()
        } label: {
            Label(playlist.isPinned ? "Открепить" : "Закрепить",
                  systemImage: playlist.isPinned ? "pin.slash" : "pin")
        }
    }
}

// MARK: - Сетка плейлистов (закрепление + перетаскивание)

/// Порядок: закреплённые первыми, затем ручной sortIndex (перетаскивание),
/// затем по дате создания.
enum PlaylistOrdering {
    static func sorted(_ playlists: [Playlist], kind: MediaKind? = nil) -> [Playlist] {
        let filtered = kind == nil ? playlists : playlists.filter { $0.kind == kind }
        return filtered.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
            return a.createdAt > b.createdAt
        }
    }
}

struct PlaylistGrid: View {
    let kind: MediaKind

    @Environment(\.modelContext) private var context
    @Query private var playlists: [Playlist]
    @Query private var allItems: [MediaItem]

    private var ordered: [Playlist] {
        PlaylistOrdering.sorted(playlists, kind: kind)
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(ordered) { playlist in
                NavigationLink(value: playlist.id) {
                    VStack(alignment: .leading, spacing: 6) {
                        PlaylistArtwork(playlist: playlist, items: items(of: playlist), size: nil)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                if playlist.isPinned {
                                    Image(systemName: "pin.fill")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                        .padding(6)
                                        .background(.black.opacity(0.35), in: Circle())
                                        .padding(8)
                                }
                            }
                        Text(playlist.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text("\(playlist.itemIDs.count) \(kind == .video ? "видео" : "треков")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .draggable(playlist.id.uuidString) {
                    PlaylistArtwork(playlist: playlist, items: items(of: playlist), size: 80)
                        .opacity(0.8)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let string = items.first, let sourceID = UUID(uuidString: string) else { return false }
                    return move(sourceID, before: playlist.id)
                }
                .contextMenu {
                    PlaylistPinButton(playlist: playlist)
                    PlaylistDeleteButton(playlist: playlist)
                }
            }
        }
    }

    private func move(_ sourceID: UUID, before targetID: UUID) -> Bool {
        var ids = ordered.map(\.id)
        guard let from = ids.firstIndex(of: sourceID),
              let to = ids.firstIndex(of: targetID), from != to else { return false }
        ids.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        let byID = Dictionary(ordered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (index, id) in ids.enumerated() {
            byID[id]?.sortIndex = index
        }
        // Закреплённые остаются сверху: порядок пересчитываем только внутри групп.
        try? context.save()
        DebugLog.shared.add("↕️ порядок плейлистов обновлён")
        return true
    }

    private func items(of playlist: Playlist) -> [MediaItem] {
        let byID = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return playlist.itemIDs.compactMap { byID[$0] }
    }
}
