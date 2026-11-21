import Foundation
import SwiftUI
import SwiftData

/// Общий контейнер сервисов приложения. Доступен и из AppIntents (без расширений).
@MainActor @Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    let engine = MediaPlayerEngine()
    let scanner = LibraryScannerService()
    let importer = FileImportService()
    let spotlight = SpotlightIndexer()

    private(set) var modelContainer: ModelContainer?
    var isConfigured = false
    /// Живой запрос поиска — общий для RootTabView (возврат вкладок) и вкладки.
    var searchQuery = ""
    private var isScanning = false
    private var rescanRequested = false

    private init() {}

    func configure(container: ModelContainer) async {
        guard !isConfigured else { return }
        isConfigured = true
        modelContainer = container
        engine.configure(container: container, nowPlaying: NowPlayingBridge(engine: engine))
        await scanner.startWatching(documents: LibraryPathResolver.documentsDirectory) {
            Task { @MainActor in
                await AppEnvironment.shared.rescanLibrary()
            }
        }
        await rescanLibrary()
    }

    /// Сканирование с защитой от наложения: повторный запрос во время
    /// сканирования просто ставится в очередь.
    func rescanLibrary() async {
        guard let container = modelContainer else { return }
        if isScanning {
            rescanRequested = true
            return
        }
        isScanning = true
        defer {
            isScanning = false
            if rescanRequested {
                rescanRequested = false
                Task { await self.rescanLibrary() }
            }
        }

        let context = ModelContext(container)
        let existing = (try? context.fetch(FetchDescriptor<MediaItem>())) ?? []
        let records = existing.map { item in
            KnownLibraryRecord(
                id: item.id,
                storageRaw: item.storageTypeRaw,
                relativePath: item.relativePath,
                bookmarkData: item.bookmarkData,
                fingerprint: itemFingerprint(item)
            )
        }
        let outcome = await scanner.scan(documents: LibraryPathResolver.documentsDirectory, known: records)
        let deletedIDs = LibrarySync.apply(outcome, context: context)
        for id in deletedIDs { spotlight.remove(id: id) }
        if !outcome.items.isEmpty {
            let updated = (try? context.fetch(FetchDescriptor<MediaItem>())) ?? []
            spotlight.reindex(items: updated)
        }
        if let first = outcome.unsupportedFileNames.first {
            importer.banner = ImportBanner(
                title: "Неподдерживаемый формат",
                message: "«\(first)» не открывается через AVFoundation. Поддерживаются: mp3, m4a, aac, flac, alac, wav, aiff, mp4, mov, m4v."
            )
        }
    }

    func handleScenePhase(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            await rescanLibrary()
        case .background:
            engine.savePlaybackPosition()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Доступ для Spotlight / AppIntents

    func mediaItem(id: UUID) -> MediaItem? {
        guard let container = modelContainer else { return nil }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    func allMediaItems() -> [MediaItem] {
        guard let container = modelContainer else { return [] }
        let context = ModelContext(container)
        return (try? context.fetch(FetchDescriptor<MediaItem>())) ?? []
    }

    func allPlaylists() -> [Playlist] {
        guard let container = modelContainer else { return [] }
        let context = ModelContext(container)
        return (try? context.fetch(FetchDescriptor<Playlist>())) ?? []
    }

    func playFromSpotlight(id: UUID) async {
        guard let item = mediaItem(id: id) else { return }
        if item.kind == .audio {
            let allAudio = allMediaItems().filter { $0.kind == .audio }
            let startIndex = allAudio.firstIndex(where: { $0.id == id }) ?? 0
            engine.playItems(allAudio.isEmpty ? [item] : allAudio, startAt: startIndex)
        } else {
            engine.playSingle(item)
        }
    }

    /// Удаление файла (с диска, если локальный), записи SwiftData и индекса Spotlight.
    func deleteMediaItem(_ item: MediaItem) {
        if engine.currentItem?.id == item.id { engine.pause() }
        engine.removeQueueItem(item)
        if item.storageType == .localDocuments,
           let path = item.relativePath,
           let url = LibraryPathResolver.absoluteURL(for: path) {
            try? FileManager.default.removeItem(at: url)
        }
        spotlight.remove(id: item.id)
        let context = item.modelContext
        context?.delete(item)
        Self.purgePlaylistReferences(to: [item.id], in: context)
        try? context?.save()
    }

    /// Убирает id удалённых медиа из itemIDs всех плейлистов — иначе
    /// счётчик «N треков» ссылается на несуществующие файлы.
    static func purgePlaylistReferences(to deletedIDs: Set<UUID>, in context: ModelContext?) {
        guard let context, !deletedIDs.isEmpty else { return }
        let playlists = (try? context.fetch(FetchDescriptor<Playlist>())) ?? []
        for playlist in playlists {
            let before = playlist.itemIDs.count
            playlist.itemIDs.removeAll { deletedIDs.contains($0) }
            if playlist.itemIDs.count != before {
                DebugLog.shared.add("🧹 плейлист «\(playlist.name)»: убрано \(before - playlist.itemIDs.count) ссылок")
            }
        }
    }

    private func itemFingerprint(_ item: MediaItem) -> FileFingerprint? {
        // На этом этапе размер/дата модификации известны только по размеру.
        // Точный отпечаток сканер вычислит сам; nil = файл проверяется заново.
        nil
    }
}
