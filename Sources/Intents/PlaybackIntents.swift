import Foundation
import AppIntents
import SwiftData

struct PlayMediaIntent: AppIntent {
    static let title: LocalizedStringResource = "Воспроизвести медиафайл"
    static let description = IntentDescription("Запускает трек или видео из библиотеки ClipDeck.")
    static let openAppWhenRun = true

    @Parameter(title: "Медиафайл")
    var target: MediaItemEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let item = AppEnvironment.shared.mediaItem(id: target.id) else {
            throw PlaybackIntentError.itemNotFound
        }
        if item.kind == .audio {
            let allAudio = AppEnvironment.shared.allMediaItems().filter { $0.kind == .audio }
            let index = allAudio.firstIndex(where: { $0.id == item.id }) ?? 0
            AppEnvironment.shared.engine.playItems(allAudio.isEmpty ? [item] : allAudio, startAt: index)
        } else {
            AppEnvironment.shared.engine.playSingle(item)
        }
        return .result()
    }
}

struct PlayPlaylistIntent: AppIntent {
    static let title: LocalizedStringResource = "Воспроизвести плейлист"
    static let description = IntentDescription("Запускает плейлист ClipDeck. Удобно для автоматизации по Bluetooth.")
    static let openAppWhenRun = true

    @Parameter(title: "Плейлист")
    var playlist: PlaylistEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let model = AppEnvironment.shared.allPlaylists().first(where: { $0.id == playlist.id }) else {
            throw PlaybackIntentError.itemNotFound
        }
        AppEnvironment.shared.engine.playPlaylist(model)
        return .result()
    }
}

struct TogglePlaybackIntent: AppIntent {
    static let title: LocalizedStringResource = "Пауза / воспроизведение"
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AppEnvironment.shared.engine.togglePlayPause()
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static let title: LocalizedStringResource = "Следующий трек"
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AppEnvironment.shared.engine.next()
        return .result()
    }
}

enum PlaybackIntentError: Error, LocalizedError {
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .itemNotFound: return "Файл не найден в библиотеке ClipDeck."
        }
    }
}
