import Foundation
import AppIntents

struct ClipDeckShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayMediaIntent(),
            phrases: [
                "Play in \(.applicationName)",
                "Play media in \(.applicationName)",
                "Включи музыку в \(.applicationName)"
            ],
            shortTitle: "Воспроизвести",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: PlayPlaylistIntent(),
            phrases: [
                "Play playlist in \(.applicationName)",
                "Start playlist in \(.applicationName)",
                "Включи плейлист в \(.applicationName)"
            ],
            shortTitle: "Плейлист",
            systemImageName: "music.note.list"
        )
        AppShortcut(
            intent: TogglePlaybackIntent(),
            phrases: [
                "Toggle playback in \(.applicationName)",
                "Пауза в \(.applicationName)"
            ],
            shortTitle: "Пауза / Play",
            systemImageName: "playpause.fill"
        )
        AppShortcut(
            intent: NextTrackIntent(),
            phrases: [
                "Next track in \(.applicationName)",
                "Следующий трек в \(.applicationName)"
            ],
            shortTitle: "Следующий трек",
            systemImageName: "forward.fill"
        )
    }
}
