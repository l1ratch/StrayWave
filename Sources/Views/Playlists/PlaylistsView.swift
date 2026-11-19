import SwiftUI
import SwiftData

struct PlaylistsView: View {
    @Environment(\.modelContext) private var context
    @Environment(MediaPlayerEngine.self) private var engine
    @Query private var playlists: [Playlist]

    @State private var showCreateAlert = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Group {
                if playlists.isEmpty {
                    ContentUnavailableView {
                        Label("Плейлистов пока нет", systemImage: "music.note.list")
                    } description: {
                        Text("Создайте плейлист и добавляйте треки через контекстное меню в библиотеке.")
                    } actions: {
                        Button("Создать плейлист") { showCreateAlert = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(playlists.sorted { $0.createdAt > $1.createdAt }) { playlist in
                            NavigationLink(value: playlist.id) {
                                Label {
                                    VStack(alignment: .leading) {
                                        Text(playlist.name)
                                        Text("\(playlist.itemIDs.count) треков")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "music.note.list")
                                }
                            }
                            .contextMenu {
                                Button { engine.playPlaylist(playlist) } label: {
                                    Label("Воспроизвести", systemImage: "play.fill")
                                }
                            }
                        }
                        .onDelete { offsets in
                            let sorted = playlists.sorted { $0.createdAt > $1.createdAt }
                            for index in offsets { context.delete(sorted[index]) }
                            try? context.save()
                        }
                    }
                }
            }
            .navigationTitle("Плейлисты")
            .navigationDestination(for: UUID.self) { id in
                if let playlist = playlists.first(where: { $0.id == id }) {
                    PlaylistDetailView(playlist: playlist)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreateAlert = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Новый плейлист", isPresented: $showCreateAlert) {
                TextField("Название", text: $newName)
                Button("Создать") {
                    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    context.insert(Playlist(name: trimmed))
                    try? context.save()
                    newName = ""
                }
                Button("Отмена", role: .cancel) { newName = "" }
            }
        }
    }
}
