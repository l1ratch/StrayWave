import SwiftUI
import SwiftData

/// Вкладка поиска (Tab role: .search) — по всей библиотеке.
///
/// Важно: `.searchable` всегда висит на одном и том же контейнере (List),
/// пустые состояния — строки внутри списка. Если переключать само дерево
/// (Group { if … }), система пересоздаёт поле поиска и не поднимает
/// клавиатуру при открытии вкладки.
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
            List {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Библиотека пуста",
                        systemImage: "music.note",
                        description: Text("Импортируйте файлы на вкладках «Музыка» и «Видео».")
                    )
                    .listRowSeparator(.hidden)
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(results) { item in
                        MediaRowView(item: item)
                            .onTapGesture { play(item) }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Поиск")
            .searchable(text: $query, prompt: "Название, исполнитель, альбом")
        }
    }

    private func play(_ item: MediaItem) {
        engine.playItems(results, startAt: results.firstIndex(where: { $0.id == item.id }) ?? 0)
    }
}
