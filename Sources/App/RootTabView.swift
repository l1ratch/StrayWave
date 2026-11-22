import SwiftUI

enum AppTab: String, Hashable, CaseIterable {
    case music, video, radio, search, more

    /// Для CI-скриншотов: simctl launch <udid> <bundle> --tab radio
    /// (или env SW_START_TAB — аргумент надёжнее: variadic-опции simctl
    /// ломали разбор).
    static func fromLaunchEnvironment() -> AppTab {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--tab"), arguments.indices.contains(index + 1) {
            let value = arguments[index + 1]
            if let tab = AppTab.allCases.first(where: { $0.rawValue == value }) { return tab }
        }
        let value = ProcessInfo.processInfo.environment["SW_START_TAB"] ?? ""
        return AppTab.allCases.first { $0.rawValue == value } ?? .music
    }
}

/// Корневая навигация: нативный TabView (Liquid Glass) + мини-плеер в accessory.
struct RootTabView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(MediaPlayerEngine.self) private var engine
    @Environment(FileImportService.self) private var importer

    @State private var selection: AppTab = AppTab.fromLaunchEnvironment()
    @State private var lastNonSearchTab: AppTab = .music
    @State private var showFullPlayer = false
    @State private var showVideoPlayer = false

    var body: some View {
        @Bindable var importer = importer

        // Мини-плеер присутствует всегда: без трека — «Не воспроизводится»,
        // с треком — живые данные.
        tabView
            .tabViewBottomAccessory {
                MiniPlayerAccessoryView {
                    // Видео раскрываем системным видеоплеером, аудио — своим.
                    if engine.currentItem?.kind == .video {
                        showVideoPlayer = true
                    } else {
                        showFullPlayer = true
                    }
                }
            }
        .onChange(of: selection) { old, new in
            if new == .search {
                if old != .search { lastNonSearchTab = old }
                SearchFieldActivator.activate()
            }
        }
        // Клавa скрыта, запроса нет — возвращаем dock на прежнюю страницу.
        // С запросом остаёмся на раскрытой области результатов.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            guard selection == .search, app.searchQuery.isEmpty else { return }
            selection = lastNonSearchTab
        }
        // Раскрытый плеер: fullScreenCover, а не sheet. Лист на iOS 26
        // измеряется в карточной геометрии с detents — именно из-за этого
        // содержимое «строилось под широкий экран» (три раунда правок
        // содержимого это не лечили: виноват был контейнер). У fullScreenCover
        // размер ровно = окно. Закрытие — явная кнопка в плеере.
        .fullScreenCover(isPresented: $showFullPlayer) {
            FullScreenAudioPlayerView()
        }
        // Видео: только системный AVPlayerViewController — со своим крестиком,
        // PiP, Live Text и скоростями. Своего оверлея больше не рисуем.
        .fullScreenCover(isPresented: $showVideoPlayer) {
            NativeVideoPlayerScreen()
        }
        // CI-скриншот: --player открывает раскрытый плеер сразу, чтобы
        // раннер мог снять его реальные пиксели (данные вместо догадок).
        .onAppear {
            if CommandLine.arguments.contains("--player") {
                showFullPlayer = true
            }
        }
        // Собственный оверлей-баннер вместо .alert: системный алерт в
        // иерархии TabView мог не показываться, поэтому этапы импорта были
        // невидимы. Оверлей отображается всегда, поверх контента.
        .overlay(alignment: .top) {
            if let banner = importer.banner {
                ImportBannerOverlay(banner: banner) {
                    withAnimation { importer.banner = nil }
                }
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
                .task(id: banner.id) {
                    try? await Task.sleep(for: .seconds(9))
                    withAnimation { importer.banner = nil }
                }
            }
        }
    }

    @ViewBuilder
    private var tabView: some View {
        TabView(selection: $selection) {
            Tab("Музыка", systemImage: "music.note", value: AppTab.music) {
                MusicLibraryView()
            }
            Tab("Видео", systemImage: "film", value: AppTab.video) {
                VideoLibraryView()
            }
            Tab("Радио", systemImage: "antenna.radiowaves.left.and.right", value: AppTab.radio) {
                RadioView()
            }
            // Порядок важен: role .search всегда прилипает к правому краю,
            // поэтому текстовые вкладки ставим ДО него — иначе последняя
            // подпись залезает под кружок поиска.
            Tab("Настройки", systemImage: "gearshape", value: AppTab.more) {
                SettingsRootView()
            }
            Tab("Поиск", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchLibraryView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
