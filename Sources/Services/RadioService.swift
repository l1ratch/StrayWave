import Foundation
import Observation

struct RadioStation: Identifiable, Hashable, Codable {
    let name: String
    let url: String
    let genre: String
    let country: String
    let region: String
    var id: String { url }
}

/// Категория для секций галереи.
struct RadioCategory: Identifiable, Hashable {
    let genre: String
    let stations: [RadioStation]
    var id: String { genre }
}

/// Онлайн-радио. Единственная сетевая функция приложения.
///
/// Играет через основной MediaPlayerEngine (тот же AVQueuePlayer) — поэтому
/// локскрин, AirPods, Dynamic Island и мини-плеер работают с радио так же,
/// как с обычными треками.
///
/// Каталог собран с rosradio-online.ru (актуальность потоков — ноябрь 2026).
/// Региональные версии часто отдают http — для этого в Info.plist включён
/// NSAllowsArbitraryLoads.
@MainActor
@Observable
final class RadioService {
    static let shared = RadioService()

    private(set) var lastError: String?

    private init() {
        AppEnvironment.shared.engine.onStreamFailure = { [weak self] message in
            self?.lastError = message
        }
    }

    // MARK: - Состояние — из движка

    var currentStation: RadioStation? {
        guard let radio = AppEnvironment.shared.engine.radioNowPlaying else { return nil }
        return allStations.first { $0.name == radio.title && $0.region == radio.subtitle }
    }

    var isPlaying: Bool {
        let engine = AppEnvironment.shared.engine
        return engine.radioNowPlaying != nil && engine.isPlaying
    }

    var isActive: Bool { AppEnvironment.shared.engine.radioNowPlaying != nil }

    // MARK: - Каталог

    static let builtInStations: [RadioStation] = [
        // Поп
        .init(name: "Русское радио", url: "https://rusradio.hostingradio.ru/rusradio96.aacp", genre: "Поп", country: "Россия", region: "Москва"),
        .init(name: "Хит FM", url: "https://hitfm.hostingradio.ru/hitfm96.aacp", genre: "Поп", country: "Россия", region: "Москва"),
        .init(name: "Like FM", url: "http://23.105.238.4/gpm-likefm495.aacp", genre: "Поп", country: "Россия", region: "Москва"),
        .init(name: "Like FM", url: "http://hls-01-gpm.hostingradio.ru/likefm812/128/playlist.m3u8", genre: "Поп", country: "Россия", region: "Санкт-Петербург"),
        .init(name: "Европа Плюс", url: "http://emgregion.hostingradio.ru:8064/moscow.europaplus.mp3", genre: "Поп", country: "Россия", region: "Москва"),
        .init(name: "Ретро FM", url: "http://emgregion.hostingradio.ru:8064/moscow.retrofm.mp3", genre: "Поп", country: "Россия", region: "Москва"),
        // Танцевальное
        .init(name: "Radio Record", url: "https://radiorecord.hostingradio.ru/rr_main96.aacp", genre: "Танцевальное", country: "Россия", region: "Федеральное"),
        // Рок
        .init(name: "Наше радио", url: "https://nashe1.hostingradio.ru/nashe-128.mp3", genre: "Рок", country: "Россия", region: "Москва"),
        // Разговорное
        .init(name: "Вести FM", url: "https://icecast-vgtrk.cdnvideo.ru/vestifm", genre: "Разговорное", country: "Россия", region: "Федеральное"),
        // Юмор
        .init(name: "Юмор FM", url: "http://23.105.238.4/gpm-humorfm495.aacp", genre: "Юмор", country: "Россия", region: "Москва")
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

    // MARK: - Фильтры

    var countries: [String] {
        Array(Set(allStations.map(\.country))).sorted()
    }

    func regions(for country: String) -> [String] {
        let order = ["Федеральное", "Москва", "Санкт-Петербург"]
        let present = Set(allStations.filter { $0.country == country }.map(\.region))
        let named = order.filter { present.contains($0) }
        let other = present.subtracting(named).sorted()
        return named + other
    }

    func filtered(country: String?, region: String?) -> [RadioCategory] {
        var list = allStations
        if let country { list = list.filter { $0.country == country } }
        if let region { list = list.filter { $0.region == region } }
        let dict = Dictionary(grouping: list) { $0.genre }
        let order = ["Мои", "Поп", "Танцевальное", "Рок", "Разговорное", "Юмор"]
        let genres = order.filter { dict[$0] != nil } + dict.keys.filter { !order.contains($0) }.sorted()
        return genres.map { RadioCategory(genre: $0, stations: dict[$0] ?? []) }
    }

    func searchResults(_ query: String) -> [RadioStation] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return allStations.filter {
            $0.name.lowercased().contains(q) || $0.genre.lowercased().contains(q) || $0.region.lowercased().contains(q)
        }
    }

    // MARK: - Управление

    func play(_ station: RadioStation) {
        let engine = AppEnvironment.shared.engine
        if currentStation == station, engine.isPlaying {
            engine.pause()
            return
        }
        guard let url = URL(string: station.url) else {
            lastError = "Некорректный адрес потока"
            return
        }
        lastError = nil
        engine.playStream(url: url, title: station.name, subtitle: station.region)
    }

    func togglePlayPause() {
        guard isActive else { return }
        let engine = AppEnvironment.shared.engine
        if engine.isPlaying { engine.pause() } else { engine.play() }
    }

    func stop() {
        AppEnvironment.shared.engine.stopStream()
    }

    func addCustom(name: String, url: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, URL(string: trimmedURL) != nil else { return }
        var list = customStations
        if !list.contains(where: { $0.url == trimmedURL }) {
            list.append(.init(name: trimmedName, url: trimmedURL, genre: "Мои", country: "Россия", region: "Моя станция"))
            customStations = list
        }
    }

    func removeCustom(_ station: RadioStation) {
        customStations.removeAll { $0.id == station.id }
        if currentStation == station { stop() }
    }
}
