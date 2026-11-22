import SwiftUI
import SwiftData
import CoreSpotlight
import UIKit

/// Ориентация задаётся НА УРОВНЕ СЦЕНЫ.
///
/// В SwiftUI-lifecycle ключ Info.plist `UISupportedInterfaceOrientations`
/// сценой не читается — ориентациями рулит UIApplicationDelegate. Без этого
/// сцена могла жить в ландшафте: SwiftUI раскладывал контент по широкому
/// окну, а `UIScreen.bounds` (не отражает ориентацию сцены на iOS 26)
/// возвращал портретную ширину — плеер «думал, что телефон на боку».
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}

@main
struct OfflineMediaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let environment = AppEnvironment.shared
    private let container: ModelContainer

    /// Под test host нельзя трогать дисковое хранилище и сканер: тесты чистые.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil

    init() {
        if !Self.isRunningTests { CrashReporter.install() }
        do {
            if Self.isRunningTests {
                container = try ModelContainer(
                    for: MediaItem.self, Playlist.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } else {
                container = try ModelContainer(for: MediaItem.self, Playlist.self)
            }
        } catch {
            fatalError("Не удалось открыть хранилище библиотеки: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(environment)
                .environment(environment.engine)
                .environment(environment.importer)
                .modelContainer(container)
                .onOpenURL { url in
                    Task { await environment.importer.handleIncomingURL(url) }
                }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                          let id = UUID(uuidString: identifier) else { return }
                    Task { await environment.playFromSpotlight(id: id) }
                }
                .task {
                    if !Self.isRunningTests {
                        await environment.configure(container: container)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    Task { await environment.handleScenePhase(phase) }
                }
        }
    }
}
