import SwiftUI
import SwiftData

struct MusicLibraryView: View {
    @Environment(MediaPlayerEngine.self) private var engine
    @Environment(AppEnvironment.self) private var app

    @Query(filter: #Predicate<MediaItem> { $0.kindRaw == "audio" })
    private var items: [MediaItem]

    @State private var sortOrder: MediaSortOrder = .dateAdded
    @State private var favoritesOnly = false
    @State private var showCreatePlaylist = false
    @State private var infoItem: MediaItem?

    private var visibleItems: [MediaItem] {
        let filtered = favoritesOnly ? items.filter(\.isFavorite) : items
        return sortOrder.sort(filtered)
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty && !favoritesOnly {
                    ContentUnavailableView {
                        Label("Музыки пока нет", systemImage: "music.note")
                    } description: {
                        Text("Скопируйте файлы в папку StrayWave в приложении «Файлы» или добавьте их кнопкой «+» — треки появятся автоматически.")
                    }
                } else {
                    List {
                        MusicPlaylistsSection()
                        if visibleItems.isEmpty {
                            ContentUnavailableView(
                                "Ничего не найдено",
                                systemImage: "magnifyingglass",
                                description: Text("Снимите фильтр «Избранное».")
                            )
                            .listRowSeparator(.hidden)
                        } else {
                            Section("Треки") {
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
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Музыка")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                PlaylistDetailResolver(id: id)
            }
            .toolbar { toolbarContent }
            .sheet(isPresented: $showCreatePlaylist) {
                PlaylistCreateSheet(kind: .audio)
            }
            .sheet(item: $infoItem) { item in
                MediaInfoSheet(item: item)
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
                    FilePickerPresenter.present { urls in
                        Task { await app.importer.importFromFiles(urls: urls) }
                    }
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
        AddToPlaylistMenu(item: item)
        Divider()
        Button { infoItem = item } label: {
            Label("Информация", systemImage: "info.circle")
        }
    }
}
