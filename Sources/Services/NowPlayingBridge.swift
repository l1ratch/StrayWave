import Foundation
import MediaPlayer
import UIKit

/// Синхронизация с локскрином / Dynamic Island / AirPods / Apple Watch.
@MainActor
final class NowPlayingBridge {
    private weak var engine: MediaPlayerEngine?
    private let center = MPRemoteCommandCenter.shared()
    private let infoCenter = MPNowPlayingInfoCenter.default()
    private var artworkTask: Task<Void, Never>?

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

        if let fileName = item.artworkFileName {
            let id = item.id
            artworkTask?.cancel()
            artworkTask = Task { [weak self] in
                guard let cgImage = await ArtworkCacheService.shared.loadImage(fileName: fileName),
                      !Task.isCancelled else { return }
                // Перерисовываем в opaque RGB: встроенные ID3-обложки бывают с
                // экзотическими цветовыми профилями (CMYK/16-bit), из-за чего
                // UIImage(cgImage:) в nowPlayingInfo приводил к крашу.
                let format = UIGraphicsImageRendererFormat.default()
                format.opaque = true
                format.scale = 1
                let targetSize = CGSize(width: cgImage.width, height: cgImage.height)
                guard targetSize.width > 0, targetSize.height > 0 else { return }
                let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
                let image = renderer.image { _ in
                    UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: targetSize))
                }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                await MainActor.run {
                    guard self?.engine?.currentItem?.id == id else { return }
                    self?.infoCenter.nowPlayingInfo?[MPMediaItemPropertyArtwork] = artwork
                }
            }
        }
        infoCenter.nowPlayingInfo = info
    }

    // MARK: - Remote commands

    private func configureCommands() {
        // MPRemoteCommandCenter вызывает обработчики на главном потоке.
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.engine?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.engine?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.engine?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.engine?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.engine?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.engine?.seek(to: positionEvent.positionTime) }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.engine?.skip(by: 15) }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.engine?.skip(by: -15) }
            return .success
        }
    }
}
