import Foundation
import AVFoundation
import MediaPlayer
import Observation

struct RadioStation: Identifiable, Hashable, Codable {
    let name: String
    let url: String
    let category: String
    var id: String { url }
}

/// Категория станций для секций (ключ по элементу кортежа не компилируется).
struct RadioCategory: Identifiable, Hashable {
    let category: String
    let stations: [RadioStation]
    var id: String { category }
}

/// Онлайн-радио. Единственная сетевая функция приложения — всё остальное
/// по-прежнему работает офлайн.
///
/// Отдельный AVPlayer: наблюдатели основного движка (таймеры позиции,
/// nowPlaying библиотеки) не должны перетирать инфо станции.
@MainActor
@Observable
final class RadioService {
    static let shared = RadioService()

    private(set) var currentStation: RadioStation?
    private(set) var isPlaying = false
    private(set) var lastError: String?

    private let player = AVPlayer()
    private var statusObservation: NSKeyValueObservation?

    private init() {}

    // MARK: - Станции

    /// Проверенные потоки (HEAD 200 на момент добавления).
    static let builtInStations: [RadioStation] = [
        .init(name: "Radio Record", url: "https://radiorecord.hostingradio.ru/rr_main96.aacp", category: "Танцевальная"),
        .init(name: "Хит FM", url: "https://hitfm.hostingradio.ru/hitfm96.aacp", category: "Поп"),
        .init(name: "Русское радио", url: "https://rusradio.hostingradio.ru/rusradio96.aacp", category: "Поп"),
        .init(name: "Наше радио", url: "https://nashe1.hostingradio.ru/nashe-128.mp3", category: "Рок"),
        .init(name: "Вести FM", url: "https://icecast-vgtrk.cdnvideo.ru/vestifm", category: "Разговорное")
    ]

    private static let customKey = "sw.radio.custom"

    var customStations: [RadioStation] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.customKey),
                  let list = try? JSONDecoder().decode([RadioStation].self, from: data) else { return [] }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.customKey)
            }
        }
    }

    var allStations: [RadioStation] { Self.builtInStations + customStations }

    var grouped: [RadioCategory] {
        let dict = Dictionary(grouping: allStations) { $0.category }
        let order = ["Мои", "Поп", "Танцевальная", "Рок", "Разговорное"]
        return order
            .filter { dict[$0] != nil }
            .map { RadioCategory(category: $0, stations: dict[$0] ?? []) }
    }

    // MARK: - Управление

    func play(_ station: RadioStation) {
        guard let url = URL(string: station.url) else {
            lastError = "Некорректный адрес потока"
            return
        }
        // Радио и библиотека не играют одновременно.
        AppEnvironment.shared.engine.pause()

        if currentStation == station, !isPlaying {
            resume()
            return
        }
        if currentStation == station, isPlaying { return }

        currentStation = station
        lastError = nil
        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let failed = item.status == .failed
            let message = item.error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, failed, self.currentStation == station else { return }
                self.lastError = message ?? "Поток недоступен"
                DebugLog.shared.add("📻 радио: ошибка потока «\(station.name)»: \(message ?? "-")")
                self.stop()
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        publishNowPlaying(for: station)
        DebugLog.shared.add("📻 радио: старт «\(station.name)»")
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateRate(0)
    }

    func resume() {
        guard currentStation != nil else { return }
        player.play()
        isPlaying = true
        updateRate(1)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        statusObservation = nil
        currentStation = nil
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func addCustom(name: String, url: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, URL(string: trimmedURL) != nil else { return }
        var list = customStations
        if !list.contains(where: { $0.url == trimmedURL }) {
            list.append(.init(name: trimmedName, url: trimmedURL, category: "Мои"))
            customStations = list
        }
    }

    func removeCustom(_ station: RadioStation) {
        customStations.removeAll { $0.id == station.id }
        if currentStation == station { stop() }
    }

    // MARK: - Lock screen

    /// Без artwork: lazy-колбэк MPMediaItemArtwork ронял процесс (подтверждено
    /// журналом диагностики). Для радио картинка не нужна.
    private func publishNowPlaying(for station: RadioStation) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: station.name,
            MPMediaItemPropertyArtist: "Радио · StrayWave",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
    }

    private func updateRate(_ rate: Double) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = rate
    }
}
