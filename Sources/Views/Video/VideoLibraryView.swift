import SwiftUI
import SwiftData

struct VideoLibraryView: View {
    @Environment(MediaPlayerEngine.self) private var engine
    @Environment(AppEnvironment.self) private var app

    @Query(filter: #Predicate<MediaItem> { $0.kindRaw == "video" })
    private var items: [MediaItem]

    @State private var sortOrder: MediaSortOrder = .dateAdded
    @State private var favoritesOnly = false
    @State private var showPlayer = false

    private var visibleItems: [MediaItem] {
        let filtered = favoritesOnly ? items.filter(\.isFavorite) : items
        return sortOrder.sort(filtered)
    }

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if visibleItems.isEmpty {
                    ContentUnavailableView {
                        Label("Видео пока нет", systemImage: "film")
                    } description: {
                        Text("Скопируйте mp4/mov/m4v в папку StrayWave в «Файлах» — они появятся здесь автоматически.")
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(visibleItems) { item in
                                VideoCell(item: item)
                                    .onTapGesture { play(item) }
                                    .contextMenu {
                                        Button { item.isFavorite.toggle() } label: {
                                            Label("Избранное", systemImage: item.isFavorite ? "heart.slash" : "heart")
                                        }
                                        Button(role: .destructive) { app.deleteMediaItem(item) } label: {
                                            Label("Удалить", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Видео")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Сортировка", selection: $sortOrder) {
                            ForEach(MediaSortOrder.allCases) { order in
                                Text(order.title).tag(order)
                            }
                        }
                        Toggle(isOn: $favoritesOnly) {
                            Label("Только избранное", systemImage: "heart")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
            .fullScreenCover(isPresented: $showPlayer) {
                NativeVideoPlayerScreen()
            }
        }
    }

    private func play(_ item: MediaItem) {
        let list = visibleItems
        let index = list.firstIndex(where: { $0.id == item.id }) ?? 0
        engine.playItems(list, startAt: index)
        showPlayer = true
    }
}

/// Ячейка сетки: превью 16:9, бейдж длительности, прогресс просмотра, значок bookmark.
private struct VideoCell: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                ArtworkImage(item: item, size: 160, cornerRadius: 10, aspectRatio: 16.0 / 9.0)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)

                Text(TimeFormatting.string(item.duration))
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.65), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(6)

                if item.storageType == .securityBookmark {
                    Image(systemName: "link")
                        .font(.caption2.weight(.bold))
                        .padding(5)
                        .background(.black.opacity(0.6), in: Circle())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(6)
                }

                // Тонкий индикатор прогресса просмотра внизу превью.
                VStack {
                    Spacer(minLength: 0)
                    if item.duration > 0, item.playbackPosition > 1 {
                        GeometryReader { geometry in
                            let fraction = min(1, item.playbackPosition / item.duration)
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.white.opacity(0.3))
                                Rectangle().fill(.blue)
                                    .frame(width: geometry.size.width * fraction)
                            }
                        }
                        .frame(height: 3)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(item.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}
