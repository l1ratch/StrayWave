import SwiftUI
import SwiftData

/// Вкладка «Ещё»: подстраницы с возможностями программы. Сверху — кружок
/// профиля со статистикой приложения и пользователя.
struct MoreView: View {
    @Query private var playlists: [Playlist]
    @Query private var items: [MediaItem]

    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            List {
                Section("Возможности") {
                    NavigationLink {
                        PlaylistsAllPage()
                    } label: {
                        Label("Все плейлисты", systemImage: "music.note.list")
                    }
                    NavigationLink {
                        SettingsPage()
                    } label: {
                        Label("Настройки", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink {
                        DebugLogView()
                    } label: {
                        Label("Журнал диагностики", systemImage: "doc.text.magnifyingglass")
                    }
                    NavigationLink {
                        AboutPage()
                    } label: {
                        Label("О программе", systemImage: "info.circle")
                    }
                }

                Section("Библиотека") {
                    LabeledContent("Файлов", value: "\(items.count)")
                    LabeledContent("Плейлистов", value: "\(playlists.count)")
                    LabeledContent("Размер медиатеки", value: Self.byteString(items.reduce(Int64(0)) { $0 + $1.fileSize }))
                }
            }
            .listStyle(.insetGrouped)
            .scrollIndicators(.hidden)
            .navigationTitle("Ещё")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showProfile = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                    }
                    .accessibilityLabel("Профиль")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                PlaylistDetailResolver(id: id)
            }
            .sheet(isPresented: $showProfile) {
                ProfileSheet()
            }
        }
    }

    static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Профиль: статистика приложения и пользователя

struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [MediaItem]
    @Query private var playlists: [Playlist]

    private var totalPlays: Int { items.reduce(0) { $0 + $1.playCount } }
    private var listenedSeconds: TimeInterval {
        items.reduce(TimeInterval(0)) { $0 + $1.duration * Double($1.playCount) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.blue, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 60, height: 60)
                            Image(systemName: "music.note")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("StrayWave")
                                .font(.headline)
                            Text("Версия \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Статистика приложения") {
                    LabeledContent("Файлов в библиотеке", value: "\(items.count)")
                    LabeledContent("Локальных копий", value: "\(items.filter { $0.storageType == .localDocuments }.count)")
                    LabeledContent("Ссылок (bookmark)", value: "\(items.filter { $0.storageType == .securityBookmark }.count)")
                    LabeledContent("Размер медиатеки", value: MoreView.byteString(items.reduce(Int64(0)) { $0 + $1.fileSize }))
                }

                Section("Моё прослушивание") {
                    LabeledContent("Всего запусков", value: "\(totalPlays)")
                    LabeledContent("Отслушано времени", value: TimeFormatting.string(listenedSeconds))
                    LabeledContent("Избранное", value: "\(items.filter(\.isFavorite).count)")
                    LabeledContent("Плейлистов", value: "\(playlists.count)")
                }
            }
            .listStyle(.insetGrouped)
            .scrollIndicators(.hidden)
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Все плейлисты (обоеих типов)

struct PlaylistsAllPage: View {
    @Query private var playlists: [Playlist]
    @Query private var allItems: [MediaItem]

    private var sorted: [Playlist] {
        playlists.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if sorted.isEmpty {
                ContentUnavailableView(
                    "Плейлистов нет",
                    systemImage: "music.note.list",
                    description: Text("Создавайте их кнопкой «+» на вкладках «Музыка» и «Видео».")
                )
            } else {
                List {
                    ForEach(sorted) { playlist in
                        NavigationLink(value: playlist.id) {
                            HStack(spacing: 12) {
                                PlaylistArtwork(playlist: playlist, items: items(of: playlist))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.name)
                                    HStack(spacing: 4) {
                                        Image(systemName: playlist.kind == .video ? "film" : "music.note")
                                            .font(.caption2)
                                        Text("\(playlist.itemIDs.count) \(playlist.kind == .video ? "видео" : "треков")")
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .contextMenu { PlaylistDeleteButton(playlist: playlist) }
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("Все плейлисты")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func items(of playlist: Playlist) -> [MediaItem] {
        let byID = Dictionary(allItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return playlist.itemIDs.compactMap { byID[$0] }
    }
}

// MARK: - Настройки

struct SettingsPage: View {
    @Environment(MediaPlayerEngine.self) private var engine

    @State private var skipInterval = AppConfig.skipInterval
    @State private var cacheCleared = false

    var body: some View {
        List {
            Section("Воспроизведение") {
                Picker("Шаг перемотки", selection: $skipInterval) {
                    Text("15 секунд").tag(15)
                    Text("30 секунд").tag(30)
                    Text("60 секунд").tag(60)
                }
                .onChange(of: skipInterval) { _, newValue in
                    AppConfig.skipInterval = newValue
                    engine.refreshRemoteSkipIntervals()
                }
                Text("Применяется к кнопкам перемотки на локскрине и в наушниках сразу.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Хранилище") {
                Button {
                    Task {
                        await ArtworkCacheService.shared.clearCache()
                        cacheCleared = true
                    }
                } label: {
                    Label("Очистить кэш обложек", systemImage: "paintbrush")
                }
                if cacheCleared {
                    Text("Кэш очищен. Обложки вырежутся заново при следующем сканировании.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Оформление") {
                Text("Стеклянные элементы подчиняются системной настройке «Уменьшить прозрачность» (Настройки → Специальные возможности).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle("Настройки")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - О программе

struct AboutPage: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        List {
            Section("StrayWave") {
                LabeledContent("Версия", value: version)
                LabeledContent("Сборка", value: build)
            }

            Section("Как это работает") {
                Text("Медиаплеер на AVFoundation и SwiftData. Ноль сторонних зависимостей, всё работает полностью офлайн — сеть нужна только вкладке «Радио».")
                    .font(.callout)
                Text("Файлы можно добавлять тремя способами: «Поделиться» из любого приложения, кнопка «+» на вкладках, папка StrayWave в приложении «Файлы».")
                    .font(.callout)
            }

            Section("Связь") {
                Link(destination: URL(string: "https://github.com/l1ratch/StrayWave")!) {
                    Label("GitHub проекта", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://github.com/l1ratch/StrayWave/issues")!) {
                    Label("Сообщить о проблеме", systemImage: "ladybug")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle("О программе")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 2) {
                Text("© 2025 l1ratch")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Все права защищены.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
        }
    }
}
