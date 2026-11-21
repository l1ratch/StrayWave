import SwiftUI
import SwiftData

/// Экран плейлиста: сверху блок с обложкой, названием, описанием и действиями,
/// ниже — список. Блок уезжает при прокрутке, в шапке остаётся inline-заголовок
/// на одной строке с кнопками.
struct PlaylistDetailView: View {
    @Bindable var playlist: Playlist
    @Environment(MediaPlayerEngine.self) private var engine
    @Query private var allItems: [MediaItem]

    @State private var showEdit = false
    @State private var infoItem: MediaItem?
    @Environment(\.dismiss) private var dismiss

    private var items: [MediaItem] {
        let byID = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return playlist.itemIDs.compactMap { byID[$0] }
    }

    var body: some View {
        List {
            Section {
                PlaylistHeader(playlist: playlist, items: items)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                    .listRowSeparator(.hidden)
            }

            if items.isEmpty {
                ContentUnavailableView(
                    "Плейлист пуст",
                    systemImage: "music.note",
                    description: Text("Добавляйте треки через контекстное меню в библиотеке.")
                )
                .listRowSeparator(.hidden)
            } else {
                Section("Треки") {
                    ForEach(items) { item in
                        MediaRowView(item: item)
                            .onTapGesture {
                                engine.playItems(items, startAt: items.firstIndex(where: { $0.id == item.id }) ?? 0)
                            }
                            .contextMenu {
                                Button { engine.playNext(item) } label: {
                                    Label("Следующим", systemImage: "text.line.first.and.arrowtriangle.forward")
                                }
                                Button { infoItem = item } label: {
                                    Label("Информация", systemImage: "info.circle")
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
        }
        .listStyle(.plain)
        // Системный индикатор прокрутки рисуется у самой кромки экрана и
        // «прыгает» при подгрузке обложек — скрываем совсем.
        .scrollIndicators(.hidden)
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    PlaylistDeleteButton(playlist: playlist) { dismiss() }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEdit = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            PlaylistEditSheet(playlist: playlist)
        }
        .sheet(item: $infoItem) { item in
            MediaInfoSheet(item: item)
        }
    }
}

/// Шапка плейлиста: обложка + заголовок + описание + действия.
private struct PlaylistHeader: View {
    let playlist: Playlist
    let items: [MediaItem]

    @Environment(MediaPlayerEngine.self) private var engine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PlaylistArtwork(playlist: playlist, items: items, size: 220, cornerRadius: 18)
                .frame(maxWidth: .infinity, alignment: .center)
                .shadow(color: .black.opacity(0.25), radius: 18, y: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.title2.weight(.bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let description = playlist.trimmedDescription {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }

            HStack(spacing: 20) {
                Button {
                    engine.playPlaylist(playlist)
                } label: {
                    Label("Слушать", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.16), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(items.isEmpty)

                Button {
                    if let first = items.first { engine.playNext(first) }
                } label: {
                    Image(systemName: "shuffle")
                        .font(.body.weight(.medium))
                        .padding(10)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(items.isEmpty)
            }
        }
    }

    private var subtitle: String {
        let unit = playlist.kind == .video ? "видео" : "треков"
        let total = items.reduce(TimeInterval(0)) { $0 + $1.duration }
        let durationPart = total > 0 ? " · \(TimeFormatting.string(total))" : ""
        return "\(items.count) \(unit)\(durationPart)"
    }
}
