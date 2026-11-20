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

    var body: some View {
        @Bindable var importer = importer

        // Аксессуару нужен реально играющий трек: с пустым содержимым система
        // всё равно рисует стеклянную панель над таб-баром.
        Group {
            if engine.currentItem != nil {
                tabView
                    .tabViewBottomAccessory {
                        MiniPlayerAccessoryView {
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
        // Лист на весь экран со свайпом вниз для закрытия. Zoom-переход
        // (.navigationTransition(.zoom) + matchedTransitionSource в мини-
        // плеере) УДАЛЁН: он выполняется ровно в момент старта
        // воспроизведения и стабильно ронял Release-сборку на устройстве
        // (SIGTRAP сразу после старта трека с обложкой).
        .sheet(isPresented: $showFullPlayer) {
            FullScreenAudioPlayerView()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
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
