import SwiftUI
import SwiftData

struct VideoLibraryView: View {
    @Environment(MediaPlayerEngine.self) private var engine
    @Environment(AppEnvironment.self) private var app

    @Query(filter: #Predicate<MediaItem> { $0.kindRaw == "video" })
    private var items: [MediaItem]

    @State private var sortOrder: MediaSortOrder = .dateAdded
    @State private var favoritesOnly = false
    @State private var showPlayer = false
    @State private var showImporter = false
    @State private var showCreatePlaylist = false
    @State private var infoItem: MediaItem?

    private var visibleItems: [MediaItem] {
        let filtered = favoritesOnly ? items.filter(\.isFavorite) : items
        return sortOrder.sort(filtered)
    }

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty && !favoritesOnly {
                    ContentUnavailableView {
                        Label("Видео пока нет", systemImage: "film")
                    } description: {
                        Text("Скопируйте mp4/mov/m4v в папку StrayWave в «Файлах» или добавьте кнопкой «+» — они появятся здесь автоматически.")
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            VideoPlaylistsStrip()
                            if visibleItems.isEmpty {
                                ContentUnavailableView(
                                    "Ничего не найдено",
                                    systemImage: "magnifyingglass",
                                    description: Text("Снимите фильтр «Избранное».")
                                )
                                .padding(.top, 60)
                            } else {
                                LazyVGrid(columns: columns, spacing: 16) {
                                    ForEach(visibleItems) { item in
                                        VideoCell(item: item)
                                            .onTapGesture { play(item) }
                                            .contextMenu { videoContextMenu(for: item) }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.bottom, 24)
                        .padding(.top, 4)
                    }
                }
            }
            .navigationTitle("Видео")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                PlaylistDetailResolver(id: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Сортировка", selection: $sortOrder) {
                            ForEach(MediaSortOrder.allCases) { order in
                                Text(order.title).tag(order)
                            }
                        }
                        Toggle(isOn: $favoritesOnly) {
                            Label("Только избранное", systemImage: "heart")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showImporter = true
                        } label: {
                            Label("Добавить из «Файлов»…", systemImage: "folder")
                        }
                        Button {
                            showCreatePlaylist = true
                        } label: {
                            Label("Новый плейлист", systemImage: "music.note.list")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showImporter) {
                DocumentPicker { urls in
                    Task { await app.importer.importFromFiles(urls: urls) }
                }
            }
            .sheet(isPresented: $showCreatePlaylist) {
                PlaylistCreateSheet(kind: .video)
            }
            .sheet(item: $infoItem) { item in
                MediaInfoSheet(item: item)
            }
            .fullScreenCover(isPresented: $showPlayer) {
                NativeVideoPlayerScreen()
            }
        }
    }

    private func play(_ item: MediaItem) {
        let list = visibleItems
        let index = list.firstIndex(where: { $0.id == item.id }) ?? 0
        engine.playItems(list, startAt: index)
        showPlayer = true
    }

    @ViewBuilder
    private func videoContextMenu(for item: MediaItem) -> some View {
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

/// Ячейка сетки: превью 16:9, бейдж длительности, прогресс просмотра, значок bookmark.
private struct VideoCell: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                ArtworkImage(item: item, size: 160, cornerRadius: 10, aspectRatio: 16.0 / 9.0)
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

            // Фиксированная высота подписи: без неё высоты ячеек меняются по
            // мере загрузки превью, и индикатор прокрутки «прыгает».
            Text(item.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
        }
    }
}
