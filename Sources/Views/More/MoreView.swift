import SwiftUI
import SwiftData

/// Вкладка «Ещё»: плейлисты, хранилище, сведения о приложении.
struct MoreView: View {
    @Environment(\.modelContext) private var context
    @Query private var playlists: [Playlist]
    @Query private var items: [MediaItem]

    @State private var editingPlaylist: Playlist?
    @State private var showCreatePlaylist = false

    private var sortedPlaylists: [Playlist] {
        playlists.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Плейлисты") {
                    if playlists.isEmpty {
                        Text("Плейлисты создаются кнопкой «+» на вкладках «Музыка» и «Видео».")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedPlaylists) { playlist in
                            NavigationLink(value: playlist.id) {
                                HStack(spacing: 12) {
                                    PlaylistArtwork(playlist: playlist, items: items(of: playlist))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                        HStack(spacing: 4) {
                                            Image(systemName: playlist.kind == .video ? "film" : "music.note")
                                                .font(.caption2)
                                            Text("\(playlist.itemIDs.count) • \(playlist.kind == .video ? "видео" : "музыка")")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        if let description = playlist.trimmedDescription {
                                            Text(description)
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                            .contextMenu {
                                Button {
                                    editingPlaylist = playlist
                                } label: {
                                    Label("Изменить", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    context.delete(playlist)
                                    try? context.save()
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section("Хранилище") {
                    LabeledContent("Файлов в библиотеке", value: "\(items.count)")
                    LabeledContent("Локальных копий", value: "\(items.filter { $0.storageType == .localDocuments }.count)")
                    LabeledContent("Ссылок (без копирования)", value: "\(items.filter { $0.storageType == .securityBookmark }.count)")
                    LabeledContent("Размер медиатеки", value: librarySizeText)
                    Text("Файлы, скопированные в папку StrayWave в приложении «Файлы» (На iPhone), сканируются автоматически.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("О приложении") {
                    LabeledContent("Версия", value: appVersion)
                    Text("Полностью оффлайн. Ноль сторонних зависимостей — только AVFoundation, SwiftData и AppIntents.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Диагностика") {
                    NavigationLink {
                        DebugLogView()
                    } label: {
                        Label("Журнал импорта и плеера", systemImage: "doc.text.magnifyingglass")
                    }
                    .font(.body)
                }
            }
            // Титул через .principal — в строке кнопок (см. MusicLibraryView).
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: UUID.self) { id in
                PlaylistDetailResolver(id: id)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Ещё").font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showCreatePlaylist = true
                        } label: {
                            Label("Новый музыкальный", systemImage: "music.note.list")
                        }
                        Button {
                            showCreateVideoPlaylist = true
                        } label: {
                            Label("Новый видео", systemImage: "film")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editingPlaylist) { playlist in
                PlaylistEditSheet(playlist: playlist)
            }
            .sheet(isPresented: $showCreatePlaylist) {
                PlaylistCreateSheet(kind: .audio)
            }
            .sheet(isPresented: $showCreateVideoPlaylist) {
                PlaylistCreateSheet(kind: .video)
            }
        }
    }

    @State private var showCreateVideoPlaylist = false

    private func items(of playlist: Playlist) -> [MediaItem] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return playlist.itemIDs.compactMap { byID[$0] }
    }

    private var librarySizeText: String {
        let bytes = items.reduce(Int64(0)) { $0 + $1.fileSize }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
