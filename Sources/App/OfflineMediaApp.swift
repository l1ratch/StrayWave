import SwiftUI
import SwiftData
import CoreSpotlight

@main
struct OfflineMediaApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let environment = AppEnvironment.shared
    private let container: ModelContainer

    /// Под test host нельзя трогать дисковое хранилище и сканер: тесты чистые.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil

    init() {
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
