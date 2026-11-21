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
    @Environment(AppEnvironment.self) private var app
    @Query private var items: [MediaItem]

    private var query: String { app.searchQuery }

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

    private var stations: [RadioStation] {
        RadioService.shared.searchResults(query)
    }

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            List {
                if items.isEmpty && stations.isEmpty {
                    ContentUnavailableView(
                        "Библиотека пуста",
                        systemImage: "music.note",
                        description: Text("Импортируйте файлы на вкладках «Музыка» и «Видео».")
                    )
                    .listRowSeparator(.hidden)
                } else if results.isEmpty && stations.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .listRowSeparator(.hidden)
                } else {
                    if !results.isEmpty {
                        Section {
                            ForEach(results) { item in
                                MediaRowView(item: item)
                                    .onTapGesture { play(item) }
                            }
                        } header: {
                            if !query.isEmpty { Text("Треки") }
                        }
                    }
                    // Радио тоже ищется — по названию, жанру, региону.
                    if !stations.isEmpty {
                        Section("Радио") {
                            ForEach(stations) { station in
                                Button {
                                    RadioService.shared.play(station)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                            .foregroundStyle(.purple)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(station.name)
                                            Text("\(station.genre) · \(station.region)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if RadioService.shared.currentStation == station {
                                            Image(systemName: "waveform")
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
            // Без титула: на вкладке поиска шапкой является сама строка поиска,
            // заголовок «Поиск» рисовался отдельной строкой ниже кнопок.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $app.searchQuery, prompt: "Название, исполнитель, альбом")
        }
    }

    private func play(_ item: MediaItem) {
        engine.playItems(results, startAt: results.firstIndex(where: { $0.id == item.id }) ?? 0)
    }
}
