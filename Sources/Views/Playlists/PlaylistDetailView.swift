import SwiftUI
import SwiftData

struct PlaylistDetailView: View {
    @Bindable var playlist: Playlist
    @Environment(MediaPlayerEngine.self) private var engine
    @Query private var allItems: [MediaItem]

    private var items: [MediaItem] {
        let byID = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return playlist.itemIDs.compactMap { byID[$0] }
    }

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView(
                    "Плейлист пуст",
                    systemImage: "music.note",
                    description: Text("Добавляйте треки через контекстное меню в библиотеке.")
                )
            } else {
                ForEach(items) { item in
                    MediaRowView(item: item)
                        .onTapGesture { engine.playItems(items, startAt: items.firstIndex(where: { $0.id == item.id }) ?? 0) }
                        .contextMenu {
                            Button { engine.playNext(item) } label: {
                                Label("Следующим", systemImage: "text.line.first.and.arrowtriangle.forward")
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                playlist.itemIDs.removeAll { $0 == item.id }
                            } label: {
                                Label("Убрать", systemImage: "minus.circle")
                            }
                        }
                }
                .onMove { offsets, destination in
                    playlist.itemIDs.move(fromOffsets: offsets, toOffset: destination)
                }
            }
        }
        .navigationTitle(playlist.name)
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        engine.playPlaylist(playlist)
                    } label: {
                        Label("Воспроизвести", systemImage: "play.fill")
                    }
                }
            }
        }
    }
}
