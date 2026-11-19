import Foundation

/// Разрешение путей библиотеки.
///
/// В базе хранится только путь относительно Documents: UUID контейнера
/// меняется при обновлениях/переустановках, абсолютный путь хранить нельзя.
enum LibraryPathResolver {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Возвращает относительный путь, если `url` лежит внутри `documents`.
    static func relativePath(for url: URL, in documents: URL = documentsDirectory) -> String? {
        let base = documents.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        guard full.hasPrefix(base) else { return nil }
        var relative = String(full.dropFirst(base.count))
        while relative.hasPrefix("/") { relative.removeFirst() }
        guard !relative.isEmpty, !relative.contains("..") else { return nil }
        return relative
    }

    /// Восстанавливает абсолютный URL по относительному пути.
    static func absoluteURL(for relativePath: String, in documents: URL = documentsDirectory) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty, !trimmed.contains("..") else { return nil }
        return documents.appendingPathComponent(trimmed, isDirectory: false)
    }

    /// Уникальный путь назначения: «song.mp3» → «song2.mp3» → «song3.mp3».
    static func uniqueDestination(for sourceName: String, in directory: URL) -> URL {
        let name = (sourceName as NSString).deletingPathExtension
        let ext = (sourceName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(sourceName)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            counter += 1
            let numbered = ext.isEmpty ? "\(name)\(counter)" : "\(name)\(counter).\(ext)"
            candidate = directory.appendingPathComponent(numbered)
        }
        return candidate
    }
}

/// Отпечаток файла для пропуска повторного чтения метаданных.
struct FileFingerprint: Equatable, Sendable {
    let size: Int64
    let modificationDate: Date

    init?(url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              let date = attributes[.modificationDate] as? Date else { return nil }
        self.size = size.int64Value
        self.modificationDate = date
    }
}

/// Чистая логика сканера, проверяемая юнит-тестами.
enum ScannerSupport {
    /// Убирает дубликаты по нормализованному пути (регистр не имеет значения).
    static func dedupe(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let key = url.standardizedFileURL.path.lowercased()
            if seen.insert(key).inserted { result.append(url) }
        }
        return result
    }

    /// Нужно ли заново читать метаданные файла.
    static func needsReimport(old: FileFingerprint?, new: FileFingerprint?) -> Bool {
        guard let new else { return false }
        return old != new
    }
}
