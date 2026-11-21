import SwiftUI
import SwiftData

/// Главная «Музыка» — медиатека в стиле Apple Music: чипы подразделов
/// сверху, ниже «Недавно добавленные» альбомы сеткой и полоса плейлистов.
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Чипы подразделов.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ChipLink(title: "Плейлисты", value: MusicRoute.playlists)
                        ChipLink(title: "Артисты", value: MusicRoute.artists)
                        ChipLink(title: "Альбомы", value: MusicRoute.albums)
                        ChipLink(title: "Песни", value: MusicRoute.songs)
                        ChipLink(title: "Избранное", value: MusicRoute.favorites)
                    }
                    .padding(.horizontal, 20)
                }

                PlaylistStrip(kind: .audio)

                // Недавно добавленные альбомы.
                VStack(alignment: .leading, spacing: 10) {
                    Text("Недавно добавленные")
                        .font(.title3.weight(.bold))
                        .padding(.horizontal, 20)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                        ForEach(albums) { group in
                            NavigationLink(value: MusicRoute.album(group.id)) {
                                AlbumCard(group: group, cover: group.coverID.flatMap { coverLookup[$0] })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
    }
}
