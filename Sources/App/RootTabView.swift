import SwiftUI

enum AppTab: Hashable {
    case music, video, search, more
}

/// Корневая навигация: нативный TabView (Liquid Glass) + мини-плеер в accessory.
struct RootTabView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(MediaPlayerEngine.self) private var engine
    @Environment(FileImportService.self) private var importer

    @State private var selection: AppTab = .music
    @State private var lastNonSearchTab: AppTab = .music
    @State private var showFullPlayer = false
    @Namespace private var playerNamespace

    static let playerTransitionID = "fullscreen-audio-player"

    var body: some View {
        @Bindable var importer = importer

        // Аксессуару нужен реально играющий трек: с пустым содержимым система
        // всё равно рисует стеклянную панель над таб-баром.
        Group {
            if engine.currentItem != nil {
                tabView
                    .tabViewBottomAccessory {
                        MiniPlayerAccessoryView(namespace: playerNamespace) {
                            showFullPlayer = true
                        }
                    }
            } else {
                tabView
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
        // Лист на весь экран: в отличие от fullScreenCover здесь есть свайп
        // вниз для закрытия, а zoom-переход от обложки работает так же.
        .sheet(isPresented: $showFullPlayer) {
            FullScreenAudioPlayerView()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .navigationTransition(.zoom(sourceID: Self.playerTransitionID, in: playerNamespace))
        }
        .alert(item: $importer.banner) { banner in
            Alert(
                title: Text(banner.title),
                message: Text(banner.message),
                dismissButton: .default(Text("OK")) { importer.banner = nil }
            )
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
            Tab("Поиск", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchLibraryView()
            }
            Tab("Ещё", systemImage: "ellipsis.circle", value: AppTab.more) {
                MoreView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
