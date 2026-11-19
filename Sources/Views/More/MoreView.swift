import SwiftUI
import SwiftData

/// Вкладка «Ещё»: плейлисты, хранилище, сведения о приложении.
struct MoreView: View {
    @Environment(\.modelContext) private var context
    @Query private var playlists: [Playlist]
    @Query private var items: [MediaItem]

    @State private var showCreatePlaylist = false
    @State private var renaming: Playlist?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Плейлисты") {
                    if playlists.isEmpty {
                        Text("Плейлисты создаются кнопкой «+» на вкладках «Музыка» и «Видео».")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(playlists.sorted { $0.createdAt > $1.createdAt }) { playlist in
                            NavigationLink(value: playlist.id) {
                                HStack(spacing: 12) {
                                    Image(systemName: playlist.kind == .video ? "film" : "music.note.list")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(playlist.name)
                                        Text("\(playlist.itemIDs.count) • \(playlist.kind == .video ? "видео" : "музыка")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .contextMenu {
                                Button {
                                    renameText = playlist.name
                                    renaming = playlist
                                } label: {
                                    Label("Переименовать", systemImage: "pencil")
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
            }
            .navigationTitle("Ещё")
            .navigationDestination(for: UUID.self) { id in
                PlaylistDetailResolver(id: id)
            }
            .sheet(isPresented: $showCreatePlaylist) {
                PlaylistCreateSheet(kind: .audio)
            }
            .alert("Переименовать плейлист", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Название", text: $renameText)
                Button("Сохранить") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        renaming?.name = trimmed
                        try? context.save()
                    }
                    renaming = nil
                }
                Button("Отмена", role: .cancel) { renaming = nil }
            }
        }
    }

    private var librarySizeText: String {
        let bytes = items.reduce(Int64(0)) { $0 + $1.fileSize }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
