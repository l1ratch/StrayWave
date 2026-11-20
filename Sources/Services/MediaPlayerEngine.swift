import Foundation
import AVFoundation
import MediaPlayer
import SwiftData
import UIKit

/// Ядро воспроизведения: AVQueuePlayer + очередь + аудиосессия + системные события.
@MainActor @Observable
final class MediaPlayerEngine {
    let player = AVQueuePlayer()

    private(set) var queueItems: [MediaItem] = []
    private(set) var isPlaying = false
    private(set) var isVideoMode = false
    /// Позиция для UI-скраббера (обновляется раз в секунду).
    private(set) var displayedPosition: TimeInterval = 0
    private(set) var queueLogic = PlaybackQueueLogic()

    var playbackSpeed: Float = 1.0 {
        didSet {
            player.defaultRate = playbackSpeed
            if isPlaying { player.rate = playbackSpeed }
        }
    }

    var currentItem: MediaItem? {
        guard let index = queueLogic.currentIndex, queueItems.indices.contains(index) else { return nil }
        return queueItems[index]
    }

    /// Пропуск ±15 сек доступен для видео и длинных аудио (>20 минут).
    var supportsSkipCommands: Bool {
        guard let item = currentItem else { return false }
        return item.kind == .video || item.duration > 20 * 60
    }

    static let availableSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    private var modelContainer: ModelContainer?
    private var saveContext: ModelContext?
    private var nowPlaying: NowPlayingBridge?
    private var knownItems: [UUID: MediaItem] = [:]
    private var itemCache: [UUID: AVPlayerItem] = [:]
    private var activeSecurityScopes: [UUID: URL] = [:]
    private var fastTimeObserver: Any?
    private var saveTimeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var systemTasks: [Task<Void, Never>] = []
    private var tickCounter = 0

    init() {
        player.defaultRate = playbackSpeed
        player.allowsExternalPlayback = true
        installObservers()
    }

    func configure(container: ModelContainer, nowPlaying: NowPlayingBridge) {
        guard modelContainer == nil else { return }
        modelContainer = container
        saveContext = ModelContext(container)
        self.nowPlaying = nowPlaying
        configureAudioSession()
        observeSystemEvents()
    }

    // MARK: - Запуск воспроизведения

    func playItems(_ items: [MediaItem], startAt index: Int = 0) {
        guard !items.isEmpty else { return }
        for item in items { knownItems[item.id] = item }
        let startID = items[min(max(index, 0), items.count - 1)].id
        queueLogic.replaceQueue(items.map(\.id), currentID: startID)
        rebuildPlayer(autoplay: true, resume: true)
    }

    func playSingle(_ item: MediaItem) {
        playItems([item], startAt: 0)
    }

    func playPlaylist(_ playlist: Playlist) {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let items = queueItemsByIDs(playlist.itemIDs, context: context)
        playItems(items, startAt: 0)
    }

    // MARK: - Транспорт

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard player.currentItem != nil else {
            if !queueItems.isEmpty { rebuildPlayer(autoplay: true, resume: true) }
            return
        }
        configureAudioSession()
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        nowPlaying?.update()
    }

    func pause() {
        player.pause()
        isPlaying = false
        savePlaybackPosition()
        nowPlaying?.update()
    }

    func next() {
        guard queueLogic.next() != nil else { return }
        queueLogic.advanceToNext()
        rebuildPlayer(autoplay: isPlaying, resume: false)
    }

    func previous() {
        // Стандартное поведение: первые секунды — предыдущий трек, иначе в начало.
        if player.currentTime().seconds > 5 {
            seek(to: 0)
            return
        }
        guard queueLogic.previous() != nil else { seek(to: 0); return }
        queueLogic.moveBackToPrevious()
        rebuildPlayer(autoplay: isPlaying, resume: false)
    }

    func jumpToQueueItem(_ item: MediaItem) {
        guard queueLogic.playOrder.contains(item.id) else { return }
        queueLogic.jumpTo(item.id)
        rebuildPlayer(autoplay: true, resume: false)
    }

    func seek(to seconds: TimeInterval) {
        let clamped = max(0, seconds)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        displayedPosition = clamped
        savePlaybackPosition()
        nowPlaying?.update()
    }

    func skip(by seconds: TimeInterval) {
        seek(to: player.currentTime().seconds + seconds)
    }

    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
    }

    func setRepeatMode(_ mode: PlaybackQueueLogic.RepeatMode) {
        queueLogic.repeatMode = mode
    }

    func toggleShuffle() {
        var rng = SplitMix64(seed: UInt64.random(in: .min ... .max))
        queueLogic.setShuffled(!queueLogic.isShuffled, rng: &rng)
        syncQueueMirror()
        rebuildPlayer(autoplay: isPlaying, preservePosition: true)
    }

    // MARK: - Очередь

    func playNext(_ item: MediaItem) {
        knownItems[item.id] = item
        queueLogic.insertNext(item.id)
        syncQueueMirror()
        rebuildPlayer(autoplay: isPlaying, preservePosition: true)
    }

    func appendToQueue(_ item: MediaItem) {
        knownItems[item.id] = item
        queueLogic.append(item.id)
        syncQueueMirror()
        if queueLogic.currentIndex == nil {
            rebuildPlayer(autoplay: false, resume: true)
        } else {
            rebuildPlayer(autoplay: isPlaying, preservePosition: true)
        }
    }

    func moveQueueItem(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        queueLogic.move(fromOffsets: offsets, toOffset: destination)
        syncQueueMirror()
        rebuildPlayer(autoplay: isPlaying, preservePosition: true)
    }

    func removeQueueItem(_ item: MediaItem) {
        let wasCurrent = currentItem?.id == item.id
        queueLogic.remove(id: item.id)
        syncQueueMirror()
        if wasCurrent {
            rebuildPlayer(autoplay: isPlaying, resume: false)
        } else {
            rebuildPlayer(autoplay: isPlaying, preservePosition: true)
        }
    }

    // MARK: - Позиция

    func savePlaybackPosition() {
        guard let item = currentItem else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds >= 0 else { return }
        item.playbackPosition = seconds
        try? saveContext?.save()
    }

    // MARK: - Private: очередь и плеер

    private func syncQueueMirror() {
        queueItems = queueLogic.playOrder.compactMap { knownItems[$0] }
    }

    private func rebuildPlayer(autoplay: Bool, resume: Bool = false, preservePosition: Bool = false) {
        syncQueueMirror()
        let preservedTime = preservePosition ? player.currentTime() : .zero
        player.pause()
        player.removeAllItems()

        guard let startIndex = queueLogic.currentIndex, queueItems.indices.contains(startIndex) else {
            currentItemDidChange(resume: false)
            isPlaying = false
            nowPlaying?.update()
            return
        }

        // В AVQueuePlayer помещаем только «текущий и далее»: прошедшие треки
        // не нужны, previous() перестраивает очередь при необходимости.
        for item in queueItems[startIndex...] {
            if let avItem = makePlayerItem(for: item) { player.insert(avItem, after: nil) }
        }
        releaseUnusedSecurityScopes()
        currentItemDidChange(resume: resume)

        if preservePosition, preservedTime.isNumeric {
            player.seek(to: preservedTime)
        } else if resume, let item = currentItem, item.resumePosition > 0 {
            player.seek(to: CMTime(seconds: item.resumePosition, preferredTimescale: 600))
        }
        if autoplay { play() } else { nowPlaying?.update() }
    }

    private func currentItemDidChange(resume: Bool) {
        guard let item = currentItem else {
            isVideoMode = false
            displayedPosition = 0
            return
        }
        DebugLog.shared.add("▶️ плеер: старт «\(item.title)» (artwork: \(item.artworkFileName ?? "нет"))")
        item.playCount += 1
        if !resume { item.playbackPosition = 0 }
        isVideoMode = item.kind == .video
        displayedPosition = resume ? item.resumePosition : 0
        configureAudioSession()
        DebugLog.shared.add("▶️ плеер: before nowPlaying.update()")
        nowPlaying?.update()
        DebugLog.shared.add("▶️ плеер: after nowPlaying.update()")
        try? saveContext?.save()
    }

    private func makePlayerItem(for item: MediaItem) -> AVPlayerItem? {
        if let cached = itemCache[item.id] { return cached }
        guard let url = resolvedURL(for: item) else {
            DebugLog.shared.add("❌ плеер: URL не резолвится: \(item.title)")
            return nil
        }
        let avItem = AVPlayerItem(url: url)
        itemCache[item.id] = avItem
        return avItem
    }

    private func resolvedURL(for item: MediaItem) -> URL? {
        switch item.storageType {
        case .localDocuments:
            guard let path = item.relativePath else { return nil }
            return LibraryPathResolver.absoluteURL(for: path)
        case .securityBookmark:
            guard let data = item.bookmarkData else { return nil }
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
            if url.startAccessingSecurityScopedResource() {
                activeSecurityScopes[item.id] = url
            }
            if isStale, let refreshed = try? url.bookmarkData() {
                item.bookmarkData = refreshed
            }
            return url
        }
    }

    private func releaseUnusedSecurityScopes() {
        let alive = Set(queueLogic.playOrder)
        for (id, url) in activeSecurityScopes where !alive.contains(id) {
            url.stopAccessingSecurityScopedResource()
            activeSecurityScopes.removeValue(forKey: id)
            itemCache.removeValue(forKey: id)
        }
    }

    private func queueItemsByIDs(_ ids: [UUID], context: ModelContext) -> [MediaItem] {
        let all = (try? context.fetch(FetchDescriptor<MediaItem>())) ?? []
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    // MARK: - Private: аудиосессия и наблюдатели

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: isVideoMode ? .moviePlayback : .default, options: [])
        try? session.setActive(true)
    }

    private func installObservers() {
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            Task { @MainActor [weak self] in
                self?.isPlaying = playing
            }
        }
        fastTimeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: nil) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.displayedPosition = max(0, time.seconds)
                self.tickCounter += 1
                if self.tickCounter % 5 == 0 { self.nowPlaying?.update() }
            }
        }
        saveTimeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 600), queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.savePlaybackPosition()
            }
        }
    }

    private func observeSystemEvents() {
        systemTasks.append(Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification) {
                let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
            }
        })
        systemTasks.append(Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
                let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                if reasonRaw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                    self?.pause() // вытащили наушники — не играем в динамик
                }
            }
        })
        systemTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .AVPlayerItemDidPlayToEndTime) {
                self?.handlePlaybackEnded()
            }
        })
        systemTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification) {
                self?.savePlaybackPosition()
            }
        })
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
        guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            pause()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
            if options.contains(.shouldResume) { play() }
        @unknown default:
            break
        }
    }

    private func handlePlaybackEnded() {
        if queueLogic.repeatMode == .one {
            player.seek(to: .zero)
            player.play()
            return
        }
        if queueLogic.next() != nil {
            queueLogic.advanceToNext()
            if player.currentItem == nil {
                // Конец физической очереди AVQueuePlayer (например, repeat .all).
                rebuildPlayer(autoplay: true, resume: false)
            } else {
                currentItemDidChange(resume: false)
            }
        } else {
            isPlaying = false
            savePlaybackPosition()
            nowPlaying?.update()
        }
    }

    // Движок живёт весь жизненный цикл приложения (singleton в AppEnvironment),
    // поэтому отдельный deinit с MainActor-состоянием не нужен.
}
