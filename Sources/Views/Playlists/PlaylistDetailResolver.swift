import SwiftUI
import SwiftData

/// Открывает плейлист по UUID из навигации (таб «Музыка»/«Видео»/«Ещё»).
struct PlaylistDetailResolver: View {
    let id: UUID
    @Query private var playlists: [Playlist]

    var body: some View {
        if let playlist = playlists.first(where: { $0.id == id }) {
            PlaylistDetailView(playlist: playlist)
        } else {
            ContentUnavailableView("Плейлист удалён", systemImage: "music.note.list")
        }
    }
}
