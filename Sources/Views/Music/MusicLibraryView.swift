import SwiftUI
import SwiftData

/// «Музыка» — страница устроена как Медиатека Apple Music: крупный заголовок
/// от левого края, строки категорий с иконками и шевронами, ниже — сетка
/// «Недавно добавлено» (альбомы по дате добавления).
struct MusicLibraryView: View {
    @Environment(AppEnvironment.self) private var app

    @Query(filter: #Predicate<MediaItem> { $0.kindRaw == "audio" })
    private var items: [MediaItem]

    @State private var showCreatePlaylist = false

    private var albums: [AlbumGroup] { LibraryGrouping.albums(from: items) }

    private var coverLookup: [UUID: MediaItem] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("Музыки пока нет", systemImage: "music.note")
                    } description: {
                        Text("Скопируйте файлы в папку StrayWave в приложении «Файлы» или добавьте их кнопкой «+» — треки появятся автоматически.")
                    }
                } else {
                    content
                }
            }
            .navigationTitle("Музыка")
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
            .navigationDestination(for: MusicRoute.self) { route in
                switch route {
                case .songs: SongsPage(kind: .audio)
                case .favorites: FavoritesPage(kind: .audio)
                case .playlists: PlaylistsPage(kind: .audio)
                case .albums: AlbumsPage()
                case .album(let id): AlbumDetailPage(albumID: id)
                case .artists: ArtistsPage()
                case .artist(let id): ArtistDetailPage(artistID: id)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                PlaylistDetailResolver(id: id)
            }
            .sheet(isPresented: $showCreatePlaylist) {
                PlaylistCreateSheet(kind: .audio)
            }
        }
    }

    private var content: some View {
        List {
            // Строки категорий — как на скрине Apple Music.
            Section {
                categoryRow("Плейлисты", icon: "music.note.list", route: .playlists)
                categoryRow("Артисты", icon: "music.mic", route: .artists)
                categoryRow("Альбомы", icon: "square.stack", route: .albums)
                categoryRow("Песни", icon: "music.note", route: .songs)
                categoryRow("Избранное", icon: "heart", route: .favorites)
            }

            Section("Недавно добавлено") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                    ForEach(albums) { group in
                        NavigationLink(value: MusicRoute.album(group.id)) {
                            AlbumCard(group: group, cover: group.coverID.flatMap { coverLookup[$0] })
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
    }

    private func categoryRow(_ title: String, icon: String, route: MusicRoute) -> some View {
        NavigationLink(value: route) {
            Label {
                Text(title)
                    .font(.body)
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
            }
        }
    }
}
