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
        // Без этого локскрин показывает заголовок, но кнопки play/pause
        // неактивны, а тап по обложке уходит не в приложение.
        UIApplication.shared.beginReceivingRemoteControlEvents()
        configureCommands()
    }

    func update() {
        guard let engine else { return }
        guard let item = engine.currentItem else {
            // Радио: тот же плеер, но MediaItem отсутствует — публикуем станцию.
            if let radio = engine.radioNowPlaying {
                infoCenter.nowPlayingInfo = [
                    MPMediaItemPropertyTitle: radio.title,
                    MPMediaItemPropertyArtist: radio.subtitle,
                    MPNowPlayingInfoPropertyPlaybackRate: engine.isPlaying ? 1.0 : 0.0
                ]
            } else {
                infoCenter.nowPlayingInfo = nil
            }
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

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = engine.supportsSkipCommands
        center.skipBackwardCommand.isEnabled = engine.supportsSkipCommands

        // Обложка на локскрине: eager-инициализатор MPMediaItemArtwork(image:),
        // картинка фиксируется здесь, на главном потоке. Именно ленивый
        // requestHandler (старый boundsSize:{...}) MediaPlayer вызывал на своём
        // потоке и это давало SIGTRAP — теперь его нет.
        if let fileName = item.artworkFileName, let image = eagerArtwork(fileName: fileName) {
            info[MPMediaItemPropertyArtwork] = image
            DebugLog.shared.add("🖼 nowPlaying: artwork (eager) применён")
        }
        // Звёздочка на локскрине: MPMediaItemPropertyRating — число 0...1;
        // сама кнопка появляется, когда приложение поддерживает ratingCommand.
        info[MPMediaItemPropertyRating] = NSNumber(value: item.isFavorite ? 1.0 : 0.0)
        infoCenter.nowPlayingInfo = info
        DebugLog.shared.add("🖼 nowPlaying: nowPlayingInfo применён")
    }

    /// Обложка для локскрина: синхронно с главного потока, ≤600 px, opaque RGB.
    private func eagerArtwork(fileName: String) -> MPMediaItemArtwork? {
        let url = ArtworkCacheService.localURL(for: fileName)
        guard let loaded = UIImage(contentsOfFile: url.path),
              loaded.size.width > 0, loaded.size.height > 0 else { return nil }
        let maxSide: CGFloat = 600
        let scale = min(1, maxSide / max(loaded.size.width, loaded.size.height))
        let size = CGSize(width: max(1, loaded.size.width * scale), height: max(1, loaded.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            loaded.draw(in: CGRect(origin: .zero, size: size))
        }
        guard normalized.size.width > 0, normalized.size.height > 0 else { return nil }
        return MPMediaItemArtwork(image: normalized)
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
            Task { @MainActor in self?.engine?.skip(by: Double(AppConfig.skipInterval)) }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.engine?.skip(by: -Double(AppConfig.skipInterval)) }
            return .success
        }

        // Звёздочка на локскрине: iOS рисует кнопку рейтинга, когда приложение
        // поддерживает ratingCommand, а в nowPlayingInfo есть
        // MPMediaItemPropertyRating (Float 0...1).
        center.ratingCommand.isEnabled = true
        center.ratingCommand.addTarget { [weak self] event in
            guard let ratingEvent = event as? MPRatingCommandEvent else { return .commandFailed }
            let liked = ratingEvent.rating >= 0.5
            Task { @MainActor in self?.engine?.setCurrentItemFavorite(liked) }
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
