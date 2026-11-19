import Foundation
import UniformTypeIdentifiers

/// Тип медиафайла в библиотеке.
enum MediaKind: String, Codable, Sendable {
    case audio
    case video

    /// Режим аудиосессии, соответствующий типу контента.
    var usesMovieAudioMode: Bool { self == .video }
}

/// Способ хранения файла: копия внутри Documents или ссылка через bookmark.
enum MediaStorageType: String, Codable, Sendable {
    case localDocuments
    case securityBookmark
}

/// Поддерживаемые нативные контейнеры (AVFoundation, без внешних кодеков).
enum SupportedFormats {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "flac", "alac", "wav", "aiff", "aif"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    /// Известные медиарасширения, которые AVFoundation не откроет (mkv, webm, ...).
    static let unsupportedMediaExtensions: Set<String> = [
        "mkv", "webm", "avi", "wmv", "flv", "ts", "m2ts", "vob", "ogv", "3gp",
        "ogg", "opus", "wma", "amr", "mid", "midi"
    ]

    static func kind(forExtension ext: String) -> MediaKind? {
        let key = ext.lowercased()
        if audioExtensions.contains(key) { return .audio }
        if videoExtensions.contains(key) { return .video }
        return nil
    }

    static func kind(for url: URL) -> MediaKind? {
        kind(forExtension: url.pathExtension)
    }

    static func isUnsupportedMedia(_ url: URL) -> Bool {
        unsupportedMediaExtensions.contains(url.pathExtension.lowercased())
    }

    /// UTI-типы для системного `.fileImporter`.
    static var importContentTypes: [UTType] {
        var types: [UTType] = []
        for ext in audioExtensions.union(videoExtensions) {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        types.append(contentsOf: [.audio, .movie])
        return types
    }
}
