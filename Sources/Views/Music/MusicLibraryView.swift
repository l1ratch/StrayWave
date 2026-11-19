import SwiftUI
import SwiftData

struct MusicLibraryView: View {
    @Environment(MediaPlayerEngine.self) private var engine
    @Environment(AppEnvironment.self) private var app

    @Query(filter: #Predicate<MediaItem> { $0.kindRaw == "audio" })
    private var items: [MediaItem]
    @Query private var playlists: [Playlist]

    @State private var sortOrder: MediaSortOrder = .dateAdded
    @State private var favoritesOnly = false
    @State private var showImporter = false
    @State private var importMode: ImportMode = .copy

    private var visibleItems: [MediaItem] {
        let filtered = favoritesOnly ? items.filter(\.isFavorite) : items
        return sortOrder.sort(filtered)
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleItems.isEmpty {
                    ContentUnavailableView {
                        Label(items.isEmpty ? "Музыки пока нет" : "Ничего не найдено", systemImage: "music.note")
                    } description: {
                        Text(items.isEmpty
                             ? "Скопируйте файлы в папку StrayWave в приложении «Файлы» (На iPhone) или импортируйте их через «+»."
                             : "Снимите фильтр «Избранное» или измените сортировку.")
                    } actions: {
                        if items.isEmpty {
                            Button("Импортировать файлы") {
                                importMode = .copy
                                showImporter = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    List {
                        ForEach(visibleItems) { item in
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
                                .contextMenu { contextMenu(for: item) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Музыка")
            .toolbar { toolbarContent }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: SupportedFormats.importContentTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await app.importer.importURLs(urls, mode: importMode) }
                case .failure(let error):
                    app.importer.banner = ImportBanner(title: "Ошибка импорта", message: error.localizedDescription)
                }
            }
        }
    }

    private func play(_ item: MediaItem) {
        let list = visibleItems
        let index = list.firstIndex(where: { $0.id == item.id }) ?? 0
        engine.playItems(list, startAt: index)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
                    importMode = .copy
                    showImporter = true
                } label: {
                    Label(ImportMode.copy.title, systemImage: ImportMode.copy.systemImage)
                }
                Button {
                    importMode = .bookmark
                    showImporter = true
                } label: {
                    Label(ImportMode.bookmark.title, systemImage: ImportMode.bookmark.systemImage)
                }
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: MediaItem) -> some View {
        Button { engine.playNext(item) } label: {
            Label("Следующим", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
        Button { engine.appendToQueue(item) } label: {
            Label("В конец очереди", systemImage: "text.append")
        }
        Button { item.isFavorite.toggle() } label: {
            Label(item.isFavorite ? "Убрать из избранного" : "В избранное", systemImage: item.isFavorite ? "heart.slash" : "heart")
        }
        if !playlists.isEmpty {
            Menu("В плейлист") {
                ForEach(playlists) { playlist in
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
