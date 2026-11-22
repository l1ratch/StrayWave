import SwiftUI
import SwiftData

/// «Музыка» — страница по образцу медиатеки Apple Music: заголовок в одну
/// строку с кнопками, строки «Все треки» / «Избранное», ниже — сетка
/// плейлистов с закреплением (pin) и перетаскиванием порядка.
///
/// Специально НЕ List: NavigationLink внутри List-секций получает системные
/// шевроны и участвует в жесте «назад» как строка — отсюда были «стрелки у
/// карточек» и «перебор всех альбомов при возврате».
struct MusicLibraryView: View {
    @Environment(AppEnvironment.self) private var app

    @Query(filter: #Predicate<MediaItem> { $0.kindRaw == "audio" })
    private var items: [MediaItem]

    @Query private var playlists: [Playlist]

    @State private var path = NavigationPath()
    @State private var showCreatePlaylist = false

    private var audioPlaylists: [Playlist] {
        PlaylistOrdering.sorted(playlists, kind: .audio)
    }

    var body: some View {
        NavigationStack(path: $path) {
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
            // Заголовок в одну строку с кнопками: слот .principal — та же
            // строка навбара; крупный шрифт даёт «медиатечный» вид.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // topBarLeading, а не principal: principal-слот система
                // центрирует по содержимому даже с maxWidth: .infinity
                // (проверено на скриншотах CI). Leading-слот физически у
                // левого края — как крупный титул медиатеки Apple Music.
                ToolbarItem(placement: .topBarLeading) {
                    Text("Музыка")
                        .font(.largeTitle.weight(.bold))
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
            VStack(alignment: .leading, spacing: 0) {
                categoryRow("Все треки", icon: "music.note") { path.append(MusicRoute.songs) }
                divider
                categoryRow("Избранное", icon: "heart") { path.append(MusicRoute.favorites) }

                if !audioPlaylists.isEmpty {
                    Text("Плейлисты")
                        .font(.title3.weight(.bold))
                        .padding(.horizontal, 20)
                        .padding(.top, 26)
                        .padding(.bottom, 12)
                    PlaylistGrid(kind: .audio)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func categoryRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 36, alignment: .leading)
                Text(title)
                    .font(.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Divider()
            .padding(.leading, 72)
    }
}

/// Квадратная плитка трека для «Недавно добавлено».
struct TrackTile: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ArtworkImage(item: item, size: nil)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
