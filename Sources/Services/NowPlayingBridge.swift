import Foundation
import MediaPlayer
import UIKit

/// Синхронизация с локскрином / Dynamic Island / AirPods / Apple Watch.
@MainActor
final class NowPlayingBridge {
    private weak var engine: MediaPlayerEngine?
    private let center = MPRemoteCommandCenter.shared()
    private let infoCenter = MPNowPlayingInfoCenter.default()

    init(engine: MediaPlayerEngine) {
        self.engine = engine
        configureCommands()
    }

    func update() {
        guard let engine, let item = engine.currentItem else {
            infoCenter.nowPlayingInfo = nil
            return
        }
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = item.title
        info[MPMediaItemPropertyArtist] = item.displayArtist
        if let album = item.album { info[MPMediaItemPropertyAlbumTitle] = album }
        info[MPMediaItemPropertyPlaybackDuration] = item.duration
        let elapsed = engine.player.currentTime().seconds
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed.isFinite ? max(0, elapsed) : 0
        info[MPNowPlayingInfoPropertyPlaybackRate] = engine.isPlaying ? engine.playbackSpeed : 0

        center.skipForwardCommand.isEnabled = engine.supportsSkipCommands
        center.skipBackwardCommand.isEnabled = engine.supportsSkipCommands

        // БИСЕКЦИЯ КРАША: обложка в nowPlayingInfo ОТКЛЮЧЕНА.
        //
        // Факты с устройства: трек без обложки играет, с обложкой — SIGTRAP
        // сразу после «nowPlayingInfo применён». Всё, что логируется, проходит
        // чисто; значит падает код, который система выполняет ПОСЛЕ присвоения
        // словаря: MediaPlayer на своём потоке вызывает requestHandler
        // MPMediaItemArtwork для отрисовки локскрина. Убираем artwork целиком:
        // если краш исчезнет — виновник подтверждён эмпирически.
        // Титул/исполнитель/альбом/длительность на локскрине остаются.
        if item.artworkFileName != nil {
            DebugLog.shared.add("🖼 nowPlaying: обложка есть, но отключена (бисекция краша)")
        }
        infoCenter.nowPlayingInfo = info
        DebugLog.shared.add("🖼 nowPlaying: nowPlayingInfo применён")
    }

    // MARK: - Remote commands
    private func configureCommands() {
        // MPRemoteCommandCenter вызывает обработчики на ПРОИЗВОЛЬНОЙ очереди,
        // не на главном. MainActor.assumeIsolated здесь ронял Release-сборку
        // (MainActor.assertIsolated failed) — как только система впервые
        // отправляла команду (локскрин, наушники, nowPlayingInfo). Поэтому
        // честный хоп на MainActor через Task.
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.engine?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.engine?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.engine?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.engine?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.engine?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.engine?.seek(to: positionEvent.positionTime) }
            return .success
        }
        let interval = AppConfig.skipInterval
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: interval)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: interval)]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.engine?.skip(by: AppConfig.skipInterval) }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.engine?.skip(by: -AppConfig.skipInterval) }
            return .success
        }
    }

    /// Переинтерфейсить интервалы после изменения настройки (без перезапуска).
    func refreshSkipIntervals() {
        let interval = AppConfig.skipInterval
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: interval)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: interval)]
    }
}
