import SwiftUI
import SwiftData

/// Главная «Видео» — медиатека в стиле Apple Music: чипы подразделов,
/// полоса плейлистов, сетка «Недавно добавленные».
struct VideoLibraryView: View {
    @Environment(AppEnvironment.self) private var app

    @Query(filter: #Predicate<MediaItem> { $0.kindRaw == "video" })
    private var items: [MediaItem]

    @State private var showCreatePlaylist = false

    private var recent: [MediaItem] {
        items.sorted { $0.dateAdded > $1.dateAdded }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("Видео пока нет", systemImage: "film")
                    } description: {
                        Text("Скопируйте mp4/mov/m4v в папку StrayWave в «Файлах» или добавьте кнопкой «+» — они появятся здесь автоматически.")
                    }
                } else {
                    content
                }
            }
            .navigationTitle("Видео")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
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
            .navigationDestination(for: VideoRoute.self) { route in
                switch route {
                case .all: VideoAllPage()
                case .favorites: FavoritesPage(kind: .video)
                case .playlists: PlaylistsPage(kind: .video)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                PlaylistDetailResolver(id: id)
            }
            .sheet(isPresented: $showCreatePlaylist) {
                PlaylistCreateSheet(kind: .video)
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ChipLink(title: "Плейлисты", value: VideoRoute.playlists)
                        ChipLink(title: "Все видео", value: VideoRoute.all)
                        ChipLink(title: "Избранное", value: VideoRoute.favorites)
                    }
                    .padding(.horizontal, 20)
                }

                PlaylistStrip(kind: .video)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Недавно добавленные")
                        .font(.title3.weight(.bold))
                        .padding(.horizontal, 20)
                    VideoGrid(items: recent)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
    }
}
