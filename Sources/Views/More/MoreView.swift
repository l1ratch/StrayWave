import SwiftUI
import SwiftData

/// Вкладка «Настройки» (бывшая «Ещё»): всё приложение в одной странице —
/// профиль со статистикой, воспроизведение, хранилище, журнал, о программе.
struct SettingsRootView: View {
    @Environment(MediaPlayerEngine.self) private var engine

    @Query private var items: [MediaItem]
    @Query private var playlists: [Playlist]

    @State private var skipInterval = AppConfig.skipInterval
    @State private var cacheCleared = false

    private var librarySize: Int64 { items.reduce(Int64(0)) { $0 + $1.fileSize } }

    var body: some View {
        NavigationStack {
            List {
                Section("Профиль") {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        Label("Статистика и прослушивание", systemImage: "person.crop.circle")
                    }
                }

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

                Section("Библиотека") {
                    LabeledContent("Файлов", value: "\(items.count)")
                    LabeledContent("Плейлистов", value: "\(playlists.count)")
                    LabeledContent("Размер медиатеки", value: Self.byteString(librarySize))
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

                Section("Приложение") {
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

                Section {
                    Text("Стеклянные элементы подчиняются системной настройке «Уменьшить прозрачность» (Настройки → Специальные возможности).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Оформление")
                }
            }
            .listStyle(.insetGrouped)
            .scrollIndicators(.hidden)
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Профиль: статистика приложения и пользователя

struct ProfileView: View {
    @Query private var items: [MediaItem]
    @Query private var playlists: [Playlist]

    private var totalPlays: Int { items.reduce(0) { $0 + $1.playCount } }
    private var listenedSeconds: TimeInterval {
        items.reduce(TimeInterval(0)) { $0 + $1.duration * Double($1.playCount) }
    }

    var body: some View {
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
                LabeledContent("Размер медиатеки", value: SettingsRootView.byteString(items.reduce(Int64(0)) { $0 + $1.fileSize }))
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
