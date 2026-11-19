import SwiftUI
import SwiftData

/// Вкладка поиска (Tab role: .search) — по всей библиотеке.
struct SearchLibraryView: View {
    @Environment(MediaPlayerEngine.self) private var engine
    @Query private var items: [MediaItem]
    @State private var query = ""

    private var results: [MediaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return items.sorted { $0.dateAdded > $1.dateAdded }
        }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || ($0.artist?.localizedCaseInsensitiveContains(trimmed) ?? false)
                || ($0.album?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Библиотека пуста",
                        systemImage: "magnifyingglass",
                        description: Text("Импортируйте файлы на вкладках «Музыка» и «Видео».")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(results) { item in
                        MediaRowView(item: item)
                            .onTapGesture { play(item) }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Поиск")
            .searchable(text: $query, prompt: "Название, исполнитель, альбом")
        }
    }

    private func play(_ item: MediaItem) {
        engine.playItems(results, startAt: results.firstIndex(where: { $0.id == item.id }) ?? 0)
    }
}
