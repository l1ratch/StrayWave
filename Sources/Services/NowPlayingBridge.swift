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

        // Обложка грузится СИНХРОННО с главного потока из маленького кэш-файла
        // (≤600 px JPEG) и нормализуется в opaque RGB. Асинхронный путь через
        // actor + Task давал краш при воспроизведении треков с встроенной
        // обложкой (экзотические цветовые профили ID3).
        if let fileName = item.artworkFileName {
            DebugLog.shared.add("🖼 nowPlaying: обложка \(fileName)")
            if let artwork = sanitizedArtwork(fileName: fileName) {
                info[MPMediaItemPropertyArtwork] = artwork
                DebugLog.shared.add("🖼 nowPlaying: artwork готов")
            } else {
                DebugLog.shared.add("🖼 nowPlaying: artwork НЕ собран (nil)")
            }
        }
        infoCenter.nowPlayingInfo = info
        DebugLog.shared.add("🖼 nowPlaying: nowPlayingInfo применён")
    }

    /// Обложка для локскрина: синхронная загрузка кэша + перерисовка в RGB.
    private func sanitizedArtwork(fileName: String) -> MPMediaItemArtwork? {
        let url = ArtworkCacheService.localURL(for: fileName)
        guard let image = UIImage(contentsOfFile: url.path),
              image.size.width > 0, image.size.height > 0 else { return nil }
        let maxSide: CGFloat = 600
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let normalized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard normalized.size.width > 0, normalized.size.height > 0 else { return nil }
        // boundsSize нулевым быть не должен — это роняло nowPlayingInfo.
        return MPMediaItemArtwork(boundsSize: normalized.size) { _ in normalized }
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
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.engine?.skip(by: 15) }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.engine?.skip(by: -15) }
            return .success
        }
    }
}
