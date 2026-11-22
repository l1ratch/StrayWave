import SwiftUI
import SwiftData

/// «Видео» — как «Музыка»: строки категорий сверху (Плейлисты / Избранное),
/// внизу — сетка «Недавно добавленные».
struct VideoLibraryView: View {
    @Environment(AppEnvironment.self) private var app

    @Query(filter: #Predicate<MediaItem> { $0.kindRaw == "video" })
    private var items: [MediaItem]

    @State private var path = NavigationPath()
    @State private var showCreatePlaylist = false

    private var recent: [MediaItem] {
        items.sorted { $0.dateAdded > $1.dateAdded }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if items.isEmpty {
                        ContentUnavailableView {
                            Label("Видео пока нет", systemImage: "film")
                        } description: {
                            Text("Скопируйте mp4/mov/m4v в папку StrayWave в «Файлах» или добавьте кнопкой «+» — они появятся здесь автоматически.")
                        }
                        .padding(.top, 60)
                    } else {
                        rows
                    }
                }
            }
            .scrollIndicators(.hidden)
            // См. MusicLibraryView: навбар скрыт, заголовок и «+» — в одной
            // строке внутри контента.
            .toolbar(.hidden, for: .navigationBar)
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Видео")
                .font(.system(size: 32, weight: .bold))
            Spacer()
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
                    .font(.title3.weight(.medium))
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            categoryRow("Плейлисты", icon: "music.note.list") { path.append(VideoRoute.playlists) }
            divider
            categoryRow("Избранное", icon: "heart") { path.append(VideoRoute.favorites) }

            if !recent.isEmpty {
                Text("Недавно добавленные")
                    .font(.title3.weight(.bold))
                    .padding(.horizontal, 20)
                    .padding(.top, 26)
                    .padding(.bottom, 12)
                VideoGrid(items: recent)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.bottom, 12)
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
