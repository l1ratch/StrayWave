import SwiftUI
import SwiftData

// MARK: - Маршруты медиатеки

enum MusicRoute: Hashable {
    case songs, favorites, playlists, albums, artists
    case album(String)
    case artist(String)
}

enum VideoRoute: Hashable {
    case all, favorites, playlists
}

// MARK: - Чип-кнопка подраздела

struct ChipLink: View {
    let title: String
    let value: AnyHashable

    var body: some View {
        NavigationLink(value: value) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator.opacity(0.4), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Карточка альбома

struct AlbumCard: View {
    let group: AlbumGroup
    let cover: MediaItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            coverBlock
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(group.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(group.artist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var coverBlock: some View {
        if let cover {
            ArtworkImage(item: cover, size: nil)
        } else {
            ZStack {
                LinearGradient(colors: [.blue.opacity(0.4), .teal.opacity(0.25)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.quarternote.3")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - Карточка видео

struct VideoCard: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .bottomTrailing) {
                ArtworkImage(item: item, size: nil)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(TimeFormatting.string(item.duration))
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(6)
            }
            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(item.displayArtist)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Горизонтальная полоса плейлистов

struct PlaylistStrip: View {
    let kind: MediaKind
    @Query private var playlists: [Playlist]
    @Query private var allItems: [MediaItem]

    private var matching: [Playlist] {
        playlists.filter { $0.kind == kind }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        if !matching.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Плейлисты")
                    .font(.title3.weight(.bold))
                    .padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(matching) { playlist in
                            NavigationLink(value: playlist.id) {
                                VStack(alignment: .leading, spacing: 6) {
                                    PlaylistArtwork(playlist: playlist, items: items(of: playlist), size: 150, cornerRadius: 10)
                                    Text(playlist.name)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                        .frame(width: 150, alignment: .leading)
                                    Text("\(playlist.itemIDs.count) \(kind == .video ? "видео" : "треков")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 150, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                PlaylistPinButton(playlist: playlist)
                                PlaylistDeleteButton(playlist: playlist)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private func items(of playlist: Playlist) -> [MediaItem] {
        let byID = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return playlist.itemIDs.compactMap { byID[$0] }
    }
}

// MARK: - Строки треков (для List на любой странице)

struct MediaTrackRows: View {
    let items: [MediaItem]
    var presentsVideoPlayer = false

    @Environment(MediaPlayerEngine.self) private var engine
    @Environment(AppEnvironment.self) private var app

    @State private var infoItem: MediaItem?
    @State private var showPlayer = false

    var body: some View {
        ForEach(items) { item in
            MediaRowView(item: item)
                .onTapGesture { play(item) }
                .swipeActions(edge: .leading) {
                    Button { engine.playNext(item) } label: {
                        Label("Следующим", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    .tint(.indigo)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { app.deleteMediaItem(item) } label: {
                        Label("Удалить", systemImage: "trash")
                    }
                    Button { item.isFavorite.toggle() } label: {
                        Label("Избранное", systemImage: item.isFavorite ? "heart.slash" : "heart")
                    }
                    .tint(.pink)
                }
                .contextMenu {
                    Button { engine.playNext(item) } label: {
                        Label("Следующим", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    AddToPlaylistMenu(item: item)
                    Button { infoItem = item } label: {
                        Label("Информация", systemImage: "info.circle")
                    }
                }
        }
        .sheet(item: $infoItem) { item in
            MediaInfoSheet(item: item)
        }
        .fullScreenCover(isPresented: $showPlayer) {
            NativeVideoPlayerScreen()
        }
    }

    private func play(_ item: MediaItem) {
        // Уже открытое/закрытое, но всё ещё текущее видео — просто показываем
        // плеер заново, без перезапуска с нуля.
        if presentsVideoPlayer, engine.currentItem?.id == item.id {
            showPlayer = true
            return
        }
        let index = items.firstIndex(where: { $0.id == item.id }) ?? 0
        if presentsVideoPlayer {
            engine.playSingle(item)
            showPlayer = true
        } else {
            engine.playItems(items, startAt: index)
        }
    }
}

// MARK: - Песни / Избранное (плоские списки)

struct SongsPage: View {
    let kind: MediaKind
    @Query private var allItems: [MediaItem]

    private var items: [MediaItem] {
        allItems.filter { $0.kind == kind }.sorted { $0.dateAdded > $1.dateAdded }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView("Пусто", systemImage: "music.note",
                                       description: Text("Добавьте файлы на главной странице."))
            } else {
                List {
                    Section { MediaTrackRows(items: items, presentsVideoPlayer: kind == .video) }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle(kind == .video ? "Все видео" : "Все треки")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FavoritesPage: View {
    let kind: MediaKind
    @Query private var allItems: [MediaItem]

    private var items: [MediaItem] {
        allItems.filter { $0.kind == kind && $0.isFavorite }
            .sorted { $0.dateAdded > $1.dateAdded }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView("Нет избранного", systemImage: "heart",
                                       description: Text("Свайп по строке — сердечко."))
            } else {
                List {
                    Section { MediaTrackRows(items: items, presentsVideoPlayer: kind == .video) }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("Избранное")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Плейлисты (полный список)

struct PlaylistsPage: View {
    let kind: MediaKind
    @Query private var playlists: [Playlist]
    @Query private var allItems: [MediaItem]
    @State private var showCreate = false

    private var matching: [Playlist] {
        playlists.filter { $0.kind == kind }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if matching.isEmpty {
                ContentUnavailableView("Плейлистов нет", systemImage: "music.note.list",
                                       description: Text("Создайте первый кнопкой «+»."))
            } else {
                List {
                    ForEach(matching) { playlist in
                        NavigationLink(value: playlist.id) {
                            HStack(spacing: 12) {
                                PlaylistArtwork(playlist: playlist, items: items(of: playlist))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.name)
                                    Text("\(playlist.itemIDs.count) \(kind == .video ? "видео" : "треков")")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .contextMenu { PlaylistDeleteButton(playlist: playlist) }
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("Плейлисты")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            PlaylistCreateSheet(kind: kind)
        }
    }

    private func items(of playlist: Playlist) -> [MediaItem] {
        let byID = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return playlist.itemIDs.compactMap { byID[$0] }
    }
}

// MARK: - Альбомы (сетка)

struct AlbumsPage: View {
    @Query private var allItems: [MediaItem]

    private var albums: [AlbumGroup] {
        LibraryGrouping.albums(from: allItems.filter { $0.kind == .audio })
    }

    private var coverLookup: [UUID: MediaItem] {
        Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                ForEach(albums) { group in
                    NavigationLink(value: MusicRoute.album(group.id)) {
                        AlbumCard(group: group, cover: group.coverID.flatMap { coverLookup[$0] })
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Альбомы")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Альбом: детали

struct AlbumDetailPage: View {
    let albumID: String
    @Environment(MediaPlayerEngine.self) private var engine
    @Query private var allItems: [MediaItem]

    private var audioItems: [MediaItem] { allItems.filter { $0.kind == .audio } }

    private var group: AlbumGroup? {
        LibraryGrouping.albums(from: audioItems).first { $0.id == albumID }
    }

    private var tracks: [MediaItem] {
        let byID = Dictionary(audioItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard let group else { return [] }
        return group.trackIDs.compactMap { byID[$0] }
    }

    var body: some View {
        Group {
            if let group {
                List {
                    Section {
                        AlbumHeader(
                            group: group,
                            tracks: tracks,
                            onPlay: { engine.playItems(tracks, startAt: 0) },
                            onPlayAt: { engine.playItems(tracks, startAt: $0) }
                        )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                    Section("Треки") {
                        MediaTrackRows(items: tracks)
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
            } else {
                ContentUnavailableView("Альбом не найден", systemImage: "music.quarternote.3")
            }
        }
        .navigationTitle(group?.title ?? "Альбом")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AlbumHeader: View {
    let group: AlbumGroup
    let tracks: [MediaItem]
    let onPlay: () -> Void
    let onPlayAt: (Int) -> Void

    @ViewBuilder
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            cover
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.title)
                    .font(.title2.weight(.bold))
                Text("\(group.artist) · \(group.itemCount) трек\(group.itemCount == 1 ? "" : "а") · \(TimeFormatting.string(group.totalDuration))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Button(action: onPlay) {
                    Label("Слушать", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.16), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(tracks.isEmpty)

                Button {
                    if let first = tracks.randomElement(),
                       let index = tracks.firstIndex(where: { $0.id == first.id }) {
                        onPlayAt(index)
                    }
                } label: {
                    Image(systemName: "shuffle")
                        .padding(10)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(tracks.isEmpty)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var cover: some View {
        if let coverItem = tracks.first(where: { $0.artworkFileName != nil }) ?? tracks.first {
            ArtworkImage(item: coverItem, size: nil)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            ZStack {
                LinearGradient(colors: [.indigo.opacity(0.5), .purple.opacity(0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.quarternote.3")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - Артисты

struct ArtistsPage: View {
    @Query private var allItems: [MediaItem]

    private var artists: [ArtistGroup] {
        LibraryGrouping.artists(from: allItems.filter { $0.kind == .audio })
    }

    private var lookup: [UUID: MediaItem] {
        Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        List {
            ForEach(artists) { artist in
                NavigationLink(value: MusicRoute.artist(artist.id)) {
                    HStack(spacing: 12) {
                        Group {
                            if let coverID = artist.coverID, let cover = lookup[coverID] {
                                ArtworkImage(item: cover, size: 48, cornerRadius: 24)
                            } else {
                                ZStack {
                                    Circle().fill(.quaternary)
                                    Image(systemName: "person.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 48, height: 48)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(artist.name)
                            Text("\(artist.trackIDs.count) треков · \(artist.albumIDs.count) альбомов")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .navigationTitle("Артисты")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ArtistDetailPage: View {    let artistID: String
    @Query private var allItems: [MediaItem]

    private var audioItems: [MediaItem] { allItems.filter { $0.kind == .audio } }

    private var artist: ArtistGroup? {
        LibraryGrouping.artists(from: audioItems).first { $0.id == artistID }
    }

    private var albums: [AlbumGroup] {
        guard let artist else { return [] }
        let ids = Set(artist.albumIDs)
        return LibraryGrouping.albums(from: audioItems).filter { ids.contains($0.id) }
    }

    private var tracks: [MediaItem] {
        let byID = Dictionary(audioItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard let artist else { return [] }
        return artist.trackIDs.compactMap { byID[$0] }
    }

    private var lookup: [UUID: MediaItem] {
        Dictionary(audioItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        Group {
            if let artist {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(artist.name)
                                .font(.title.weight(.bold))
                            Text("\(artist.trackIDs.count) треков · \(artist.albumIDs.count) альбомов")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .listRowSeparator(.hidden)
                    }

                    if !albums.isEmpty {
                        Section("Альбомы") {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                                ForEach(albums) { group in
                                    NavigationLink(value: MusicRoute.album(group.id)) {
                                        AlbumCard(group: group, cover: group.coverID.flatMap { lookup[$0] })
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Section("Песни") {
                        MediaTrackRows(items: tracks)
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
            } else {
                ContentUnavailableView("Артист не найден", systemImage: "person")
            }
        }
        .navigationTitle(artist?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Видео: сетка (главная и подстраница «Все видео»)

/// Ячейка сетки: превью 16:9, бейдж длительности, прогресс просмотра, значок ссылки.
struct VideoCell: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                ArtworkImage(item: item, size: nil, aspectRatio: 16.0 / 9.0)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)

                Text(TimeFormatting.string(item.duration))
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    // Системный материал: уважает «Уменьшить прозрачность».
                    .background(.thinMaterial, in: Capsule())
                    .padding(6)

                if item.storageType == .securityBookmark {
                    Image(systemName: "link")
                        .font(.caption2.weight(.bold))
                        .padding(5)
                        .background(.regularMaterial, in: Circle())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(6)
                }

                // Тонкий индикатор прогресса просмотра внизу превью.
                VStack {
                    Spacer(minLength: 0)
                    if item.duration > 0, item.playbackPosition > 1 {
                        GeometryReader { geometry in
                            let fraction = min(1, item.playbackPosition / item.duration)
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.white.opacity(0.3))
                                Rectangle().fill(.blue)
                                    .frame(width: geometry.size.width * fraction)
                            }
                        }
                        .frame(height: 3)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Фиксированная высота подписи: без неё высоты ячеек «прыгают».
            Text(item.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
        }
    }
}

struct VideoGrid: View {
    let items: [MediaItem]

    @Environment(MediaPlayerEngine.self) private var engine
    @Environment(AppEnvironment.self) private var app

    @State private var showPlayer = false
    @State private var infoItem: MediaItem?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(items) { item in
                VideoCell(item: item)
                    .onTapGesture { play(item) }
                    .contextMenu {
                        Button { item.isFavorite.toggle() } label: {
                            Label("Избранное", systemImage: item.isFavorite ? "heart.slash" : "heart")
                        }
                        AddToPlaylistMenu(item: item)
                        Button { infoItem = item } label: {
                            Label("Информация", systemImage: "info.circle")
                        }
                        Button(role: .destructive) { app.deleteMediaItem(item) } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            NativeVideoPlayerScreen()
        }
        .sheet(item: $infoItem) { item in
            MediaInfoSheet(item: item)
        }
    }

    private func play(_ item: MediaItem) {
        // Текущее видео открываем без перезапуска (см. MediaTrackRows).
        if engine.currentItem?.id == item.id {
            showPlayer = true
            return
        }
        let index = items.firstIndex(where: { $0.id == item.id }) ?? 0
        engine.playItems(items, startAt: index)
        showPlayer = true
    }
}

struct VideoAllPage: View {
    @Query private var allItems: [MediaItem]

    private var videos: [MediaItem] {
        allItems.filter { $0.kind == .video }.sorted { $0.dateAdded > $1.dateAdded }
    }

    var body: some View {
        Group {
            if videos.isEmpty {
                ContentUnavailableView("Видео пока нет", systemImage: "film")
            } else {
                ScrollView {
                    VideoGrid(items: videos)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("Все видео")
        .navigationBarTitleDisplayMode(.inline)
    }
}
