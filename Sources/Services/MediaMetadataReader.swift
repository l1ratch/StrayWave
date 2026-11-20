import Foundation
import AVFoundation
import CoreMedia
import UniformTypeIdentifiers

/// Одна строка «параметр — значение» в инфо-листе.
struct MediaDetailRow: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let value: String
}

/// Секция инфо-листа. Пустые секции не создаются.
struct MediaDetailSection: Identifiable, Sendable {
    let id = UUID()
    let title: String
    var rows: [MediaDetailRow]
}

struct MediaFileDetail: Sendable {
    var title: String
    var subtitle: String
    var hasArtwork: Bool
    var sections: [MediaDetailSection]
}

/// Sendable-слепок записи, передаваемый в actor (сам @Model через границу
/// изоляции не переносится).
struct MediaInfoRequest: Sendable {
    let title: String
    let subtitle: String
    let storageType: MediaStorageType
    let relativePath: String?
    let bookmarkData: Data?
    let duration: TimeInterval
    let fileSize: Int64
    let dateAdded: Date
    let playCount: Int
    let isFavorite: Bool
    let kind: MediaKind
    let artworkFileName: String?
}

/// Полное чтение метаданных медиафайла: контейнер, дорожки, кодеки, теги.
/// Работает в фоне (actor), MainActor не блокируется.
actor MediaMetadataReader {
    static let shared = MediaMetadataReader()

    func detail(for request: MediaInfoRequest) async -> MediaFileDetail {
        guard let resolved = resolveURL(for: request) else {
            return MediaFileDetail(
                title: request.title,
                subtitle: request.subtitle,
                hasArtwork: false,
                sections: [MediaDetailSection(title: "Файл", rows: [
                    MediaDetailRow(label: "Состояние", value: "Файл недоступен: ссылка потеряна или носитель отключён")
                ])]
            )
        }
        defer { if resolved.startedScope { resolved.url.stopAccessingSecurityScopedResource() } }

        let url = resolved.url
        let asset = AVURLAsset(url: url)
        var sections: [MediaDetailSection] = []
        sections.append(fileSection(request: request, url: url))
        sections.append(contentsOf: await playbackSection(asset: asset, url: url, request: request))
        sections.append(contentsOf: await audioSection(asset: asset))
        sections.append(contentsOf: await videoSection(asset: asset))
        sections.append(contentsOf: await tagsSection(asset: asset))
        sections.removeAll { $0.rows.isEmpty }

        return MediaFileDetail(
            title: request.title,
            subtitle: request.subtitle,
            hasArtwork: request.artworkFileName != nil || await hasEmbeddedArtwork(asset: asset),
            sections: sections
        )
    }

    // MARK: - Файл

    private func fileSection(request: MediaInfoRequest, url: URL) -> MediaDetailSection {
        var rows: [MediaDetailRow] = [.init(label: "Имя файла", value: url.lastPathComponent)]
        switch request.storageType {
        case .localDocuments:
            rows.append(.init(label: "Хранилище", value: "Копия в приложении"))
            if let path = request.relativePath {
                rows.append(.init(label: "Путь", value: "StrayWave/\(path)"))
            }
        case .securityBookmark:
            rows.append(.init(label: "Хранилище", value: "Ссылка (без копирования)"))
            rows.append(.init(label: "Расположение", value: url.deletingLastPathComponent().path))
        }
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) {
            if let size = values.fileSize {
                rows.append(.init(label: "Размер", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))
            }
            if let date = values.contentModificationDate {
                rows.append(.init(label: "Изменён", value: Self.dateFormatter.string(from: date)))
            }
        }
        rows.append(.init(label: "Добавлен", value: Self.dateFormatter.string(from: request.dateAdded)))
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()) {
            var text = type.identifier
            if type.conforms(to: .movie) { text += " · видео" }
            else if type.conforms(to: .audio) { text += " · аудио" }
            if let mime = type.preferredMIMEType { text += " · \(mime)" }
            rows.append(.init(label: "Контейнер", value: text))
        }
        rows.append(.init(label: "Проигран раз", value: "\(request.playCount)"))
        if request.isFavorite { rows.append(.init(label: "Избранное", value: "да")) }
        return MediaDetailSection(title: "Файл", rows: rows)
    }

    // MARK: - Воспроизведение

    private func playbackSection(asset: AVAsset, url: URL, request: MediaInfoRequest) async -> [MediaDetailSection] {
        var rows: [MediaDetailRow] = []
        let duration = (try? await asset.load(.duration)) ?? .zero
        if duration.isNumeric, duration.seconds > 0 {
            rows.append(.init(label: "Длительность", value: TimeFormatting.string(duration.seconds)))
            let size = fileSize(url)
            if size > 0 {
                let kbps = Double(size) * 8 / duration.seconds / 1000
                rows.append(.init(label: "Средний битрейт", value: String(format: "%.0f кбит/с", kbps)))
            }
        }
        if (try? await asset.load(.isReadable)) == true {
            rows.append(.init(label: "Проверяемость", value: "AVFoundation читает файл"))
        }
        if (try? await asset.load(.hasProtectedContent)) == true {
            rows.append(.init(label: "Защита", value: "DRM-контент"))
        }
        return [MediaDetailSection(title: "Воспроизведение", rows: rows)]
    }

    private func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
    }

    // MARK: - Аудио

    private func audioSection(asset: AVAsset) async -> [MediaDetailSection] {
        let tracks = ((try? await asset.load(.tracks)) ?? []).filter { $0.mediaType == .audio }
        guard !tracks.isEmpty else { return [] }
        var rows: [MediaDetailRow] = [.init(label: "Дорожек", value: "\(tracks.count)")]
        for (index, track) in tracks.enumerated() {
            let prefix = tracks.count > 1 ? "Дорожка \(index + 1): " : ""
            if let code = try? await track.load(.languageCode),
               let localized = Locale(identifier: code).localizedString(forLanguageCode: code) {
                rows.append(.init(label: prefix + "Язык", value: localized.capitalized))
            }
            if let rate = try? await track.load(.estimatedDataRate), rate > 0 {
                rows.append(.init(label: prefix + "Битрейт", value: String(format: "%.0f кбит/с", rate / 1000)))
            }
            for desc in (try? await track.load(.formatDescriptions)) ?? [] {
                rows.append(contentsOf: audioFormatRows(desc, prefix: prefix))
            }
        }
        return [MediaDetailSection(title: "Аудио", rows: rows)]
    }

    private func audioFormatRows(_ desc: CMFormatDescription, prefix: String) -> [MediaDetailRow] {
        var rows: [MediaDetailRow] = [.init(label: prefix + "Кодек", value: codecName(CMFormatDescriptionGetMediaSubType(desc)))]
        guard CMFormatDescriptionGetTypeID(desc) == CMAudioFormatDescriptionGetTypeID() else { return rows }
        let audioDesc: CMAudioFormatDescription = unsafeBitCast(desc, to: CMAudioFormatDescription.self)
        guard let pointer = CMAudioFormatDescriptionGetStreamBasicDescription(audioDesc) else { return rows }
        let asbd = pointer.pointee
        if asbd.mSampleRate > 0 {
            rows.append(.init(label: prefix + "Частота дискретизации", value: String(format: "%.0f Гц", asbd.mSampleRate)))
        }
        if asbd.mChannelsPerFrame > 0 {
            let channels = Int(asbd.mChannelsPerFrame)
            let name = channels == 1 ? "моно" : (channels == 2 ? "стерео" : "многоканальный")
            rows.append(.init(label: prefix + "Каналы", value: "\(channels) (\(name))"))
        }
        if asbd.mBitsPerChannel > 0 {
            rows.append(.init(label: prefix + "Разрядность", value: "\(asbd.mBitsPerChannel) бит"))
        }
        return rows
    }

    // MARK: - Видео

    private func videoSection(asset: AVAsset) async -> [MediaDetailSection] {
        let tracks = ((try? await asset.load(.tracks)) ?? []).filter { $0.mediaType == .video }
        guard !tracks.isEmpty else { return [] }
        var rows: [MediaDetailRow] = []
        let characteristics = (try? await asset.load(.availableMediaCharacteristics)) ?? []
        if characteristics.contains(.containsHDRVideo) {
            rows.append(.init(label: "HDR", value: "есть"))
        }
        for (index, track) in tracks.enumerated() {
            let prefix = tracks.count > 1 ? "Дорожка \(index + 1): " : ""
            if let size = try? await track.load(.naturalSize), size.width > 0, size.height > 0 {
                rows.append(.init(label: prefix + "Разрешение", value: "\(Int(size.width))×\(Int(size.height))"))
                if let transform = try? await track.load(.preferredTransform) {
                    let rect = CGRect(origin: .zero, size: size).applying(transform)
                    let width = Int(abs(rect.width)), height = Int(abs(rect.height))
                    if width > 1, height > 1, (width, height) != (Int(size.width), Int(size.height)) {
                        rows.append(.init(label: prefix + "Отображение", value: "\(width)×\(height)"))
                    }
                }
            }
            if let frameRate = try? await track.load(.nominalFrameRate), frameRate > 0 {
                rows.append(.init(label: prefix + "Частота кадров", value: String(format: "%.2f к/с", frameRate)))
            }
            for desc in (try? await track.load(.formatDescriptions)) ?? [] {
                rows.append(.init(label: prefix + "Кодек", value: codecName(CMFormatDescriptionGetMediaSubType(desc))))
                if CMFormatDescriptionGetTypeID(desc) == CMVideoFormatDescriptionGetTypeID() {
                    let videoDesc: CMVideoFormatDescription = unsafeBitCast(desc, to: CMVideoFormatDescription.self)
                    let encoded = CMVideoFormatDescriptionGetDimensions(videoDesc)
                    if encoded.width > 0, encoded.height > 0 {
                        rows.append(.init(label: prefix + "Кодированное разрешение", value: "\(encoded.width)×\(encoded.height)"))
                    }
                    let clean = CMVideoFormatDescriptionGetCleanAperture(videoDesc, false)
                    if clean.width > 1, clean.height > 1 {
                        rows.append(.init(label: prefix + "Clean aperture", value: "\(Int(clean.width))×\(Int(clean.height))"))
                    }
                }
            }
        }
        return [MediaDetailSection(title: "Видео", rows: rows)]
    }

    // MARK: - Теги

    private static let tagLabels: [String: String] = [
        "title": "Название", "artist": "Исполнитель", "albumName": "Альбом",
        "albumArtist": "Альбом-исполнитель", "author": "Автор", "creator": "Создатель",
        "composer": "Композитор", "lyricist": "Текст песни", "genre": "Жанр",
        "creationDate": "Дата записи", "year": "Год", "trackNumber": "Номер трека",
        "diskNumber": "Номер диска", "artwork": "Обложка", "description": "Описание"
    ]

    private func tagsSection(asset: AVAsset) async -> [MediaDetailSection] {
        var rows: [MediaDetailRow] = []
        let items = (try? await asset.load(.metadata)) ?? []
        for entry in items {
            // Читаем свойства напрямую — без batch-load и протокола-провайдера.
            let label = tagLabel(entry)
            guard !label.isEmpty else { continue }
            if let string = entry.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
                rows.append(.init(label: label, value: string))
            } else if let number = entry.numberValue {
                rows.append(.init(label: label, value: label == "Обложка" ? "есть" : "\(number)"))
            } else if let date = entry.dateValue {
                rows.append(.init(label: label, value: Self.dateFormatter.string(from: date)))
            } else if entry.dataValue != nil, label == "Обложка" {
                rows.append(.init(label: label, value: "есть"))
            }
        }
        var seen = Set<String>()
        rows = rows.filter { seen.insert($0.label).inserted }
        guard !rows.isEmpty else { return [] }
        return [MediaDetailSection(title: "Теги", rows: rows)]
    }

    private static let id3Labels: [String: String] = [
        "TIT2": "Название", "TP1": "Исполнитель", "TALB": "Альбом", "TPE2": "Альбом-исполнитель",
        "TCOM": "Композитор", "TCON": "Жанр", "TYER": "Год", "TDRC": "Год записи",
        "TRCK": "Номер трека", "TPOS": "Номер диска", "TPE1": "Исполнитель", "COMM": "Комментарий"
    ]

    private func tagLabel(_ item: AVMetadataItem) -> String {
        if let common = item.commonKey {
            return Self.tagLabels[common.rawValue] ?? common.rawValue
        }
        guard let key = item.keyIdentifier else { return "" }
        if item.keySpace == .common { return Self.tagLabels[key] ?? key }
        if item.keySpace == .iTunesMetadata {
            switch key {
            case "sonm": return "Композитор"
            case "desc": return "Описание"
            case "lyrs": return "Текст"
            case "grp c": return "Группировка"
            default: return ""
            }
        }
        if item.keySpace == .ID3Metadata { return Self.id3Labels[key] ?? "" }
        if item.keySpace == .quickTimeMetadata { return Self.tagLabels[key] ?? key }
        return ""
    }

    private func hasEmbeddedArtwork(asset: AVAsset) async -> Bool {
        let items = (try? await asset.load(.commonMetadata)) ?? []
        return AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork).isEmpty == false
    }

    // MARK: - Утилиты

    private struct ResolvedMedia {
        let url: URL
        let startedScope: Bool
    }

    private func resolveURL(for request: MediaInfoRequest) -> ResolvedMedia? {
        switch request.storageType {
        case .localDocuments:
            guard let path = request.relativePath,
                  let url = LibraryPathResolver.absoluteURL(for: path),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ResolvedMedia(url: url, startedScope: false)
        case .securityBookmark:
            guard let data = request.bookmarkData,
                  let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: nil),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ResolvedMedia(url: url, startedScope: url.startAccessingSecurityScopedResource())
        }
    }

    private func codecName(_ raw: OSType) -> String {
        var value = raw.bigEndian
        let text = withUnsafeBytes(of: &value) { buffer in
            String(bytes: buffer.prefix(4).filter { $0 != 0 }, encoding: .ascii) ?? ""
        }
        // Swift не допускает «\0» в литерале — только экранированный скаляр.
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{0000}\u{0020}"))
        guard !trimmed.isEmpty else { return "неизвестно" }
        let readable: [String: String] = [
            "mp4a": "AAC", ".mp3": "MP3", "aacs": "AAC", "alac": "ALAC", "fLaC": "FLAC",
            "ac-3": "AC-3", "ec-3": "E-AC-3", "lpcm": "PCM", "mlpa": "MLP",
            "avc1": "H.264", "avc3": "H.264", "hvc1": "HEVC", "hev1": "HEVC", "mp4v": "MPEG-4",
            "jpeg": "Motion JPEG", "apcn": "Apple ProRes 422", "ap4h": "ProRes 4444",
            "pnyu": "Uncompressed 4:2:2"
        ]
        if let name = readable[trimmed] { return "\(name) (\(trimmed))" }
        return trimmed
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
