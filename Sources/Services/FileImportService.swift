import Foundation
import SwiftUI
import SwiftData

/// Одноразовое сообщение-баннер (ошибка формата, результат импорта).
struct ImportBanner: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let message: String
}

/// Импорт файлов.
///
/// Две модели хранения, обе без выбора режима пользователем:
/// • «Поделиться» / «Открыть в…» → копия файла в Documents приложения
///   (файл гарантированно офлайн, источник может быть временным);
/// • выбор через встроенный импорт из «Файлов» → Security-Scoped Bookmark,
///   файл остаётся на диске/носителе и НЕ копируется.
@MainActor @Observable
final class FileImportService {
    var banner: ImportBanner?

    // MARK: - «Открыть в…» / «Поделиться» → копия в Documents

    func handleIncomingURL(_ url: URL) async {
        guard url.isFileURL else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard SupportedFormats.kind(for: url) != nil else {
            banner = ImportBanner(
                title: "Неподдерживаемый формат",
                message: "«\(url.lastPathComponent)» нельзя открыть через AVFoundation. Поддерживаются: mp3, m4a, aac, flac, alac, wav, aiff, mp4, mov, m4v."
            )
            return
        }
        do {
            _ = try copyIntoDocuments(url)
            await AppEnvironment.shared.rescanLibrary()
        } catch let skip as ImportSkipped {
            switch skip {
            case .alreadyInLibrary(let name):
                banner = ImportBanner(
                    title: "Уже в библиотеке",
                    message: "«\(name)» с таким содержимым уже добавлен — копия не создана."
                )
            }
        } catch {
            banner = ImportBanner(title: "Ошибка импорта", message: error.localizedDescription)
        }
    }

    // MARK: - Импорт из «Файлов» → ссылка без копирования

    func importFromFiles(urls: [URL]) async {
        // Видимая диагностика цепочки: если этот баннер не появился вообще —
        // не сработал сам пикер, если появился, а файлов нет — проблема в
        // сохранении/сканере. По тексту пользователь видит, где обрыв.
        banner = ImportBanner(title: "Импорт из «Файлов»", message: "Выбрано: \(urls.count). Сохраняю ссылки…")

        var linkedFiles = 0
        var skippedCopied = 0
        var failed = 0
        var firstError: String?

        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    for file in mediaFiles(inside: url) {
                        if try saveBookmark(file) { linkedFiles += 1 } else { skippedCopied += 1 }
                    }
                } else if SupportedFormats.isUnsupportedMedia(url) {
                    failed += 1
                } else if SupportedFormats.kind(for: url) == nil {
                    continue
                } else if try saveBookmark(url) {
                    linkedFiles += 1
                } else {
                    skippedCopied += 1
                }
            } catch {
                failed += 1
                if firstError == nil { firstError = error.localizedDescription }
            }
        }

        if failed > 0 {
            banner = ImportBanner(
                title: "Ошибка импорта",
                message: firstError ?? "AVFoundation не умеет эти контейнеры. Поддерживаются: mp3, m4a, aac, flac, alac, wav, aiff, mp4, mov, m4v."
            )
        } else if skippedCopied > 0 && linkedFiles == 0 {
            banner = ImportBanner(
                title: "Уже в библиотеке",
                message: "Файлы из папки StrayWave в «Файлах» добавляются автоматически — отдельно их импортировать не нужно."
            )
        } else if linkedFiles > 0 {
            // Позитивная обратная связь: видно, что импорт действительно случился.
            banner = ImportBanner(
                title: "Добавлено в библиотеку",
                message: "Ссылок на файлы: \(linkedFiles). Копирование не требовалось — треки читаются с исходного места."
            )
        }
        if linkedFiles > 0 { await AppEnvironment.shared.rescanLibrary() }
    }

    // MARK: - Private

    private func mediaFiles(inside directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var result: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            guard SupportedFormats.kind(for: url) != nil else { continue }
            result.append(url)
        }
        return result
    }

    /// Возвращает false, если файл уже есть в библиотеке (копия или bookmark).
    private func saveBookmark(_ url: URL) throws -> Bool {
        guard LibraryPathResolver.relativePath(for: url) == nil else { return false }
        guard existingCopy(of: url) == nil else { return false }
        // На iOS bookmark всегда security-scoped; опция .withSecurityScope —
        // macOS-only, на iOS недоступна. Поэтому options: [].
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        guard let container = AppEnvironment.shared.modelContainer else { return true }
        let context = ModelContext(container)

        // Не плодим bookmark-дубли: та же целевая ссылка = уже есть в базе.
        let existing = (try? context.fetch(FetchDescriptor<MediaItem>())) ?? []
        let targetPath = url.standardizedFileURL.path
        for record in existing where record.storageType == .securityBookmark {
            guard let recordData = record.bookmarkData else { continue }
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: recordData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
               resolved.standardizedFileURL.path == targetPath {
                return false
            }
        }

        let item = MediaItem(
            kind: SupportedFormats.kind(for: url) ?? .audio,
            storageType: .securityBookmark,
            bookmarkData: data,
            title: url.deletingPathExtension().lastPathComponent
        )
        context.insert(item)
        try context.save()
        return true
    }

    /// Уже есть файл с таким именем и размером — дубликат не создаём.
    private func existingCopy(of url: URL) -> URL? {
        let documents = LibraryPathResolver.documentsDirectory
        let normalizedName = Self.normalize(name: url.lastPathComponent).lowercased()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? -1
        guard let enumerator = FileManager.default.enumerator(
            at: documents,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        while let candidate = enumerator.nextObject() as? URL {
            guard Self.normalize(name: candidate.lastPathComponent).lowercased() == normalizedName else { continue }
            let candidateSize = (try? candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? -2
            if candidateSize == size { return candidate }
        }
        return nil
    }

    /// «Трек (1).mp3» → «Трек.mp3»: при пересылке iOS дописывает счётчики,
    /// из-за чего один и тот же файл превращался в дубли библиотеки.
    private static func normalize(name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var trimmed = base
        while let range = trimmed.range(of: #"\s*[((]\s*(?:[1-9]|[1-2][0-9]|3[0-2])\s*[))]\s*$"#, options: .regularExpression) {
            trimmed.removeSubrange(range)
        }
        return ext.isEmpty ? trimmed : "\(trimmed).\(ext)"
    }

    private func copyIntoDocuments(_ url: URL) throws -> URL {
        let documents = LibraryPathResolver.documentsDirectory
        if !url.hasDirectoryPath, let existing = existingCopy(of: url) {
            throw ImportSkipped.alreadyInLibrary(existing.lastPathComponent)
        }
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let finalName = isDirectory.boolValue ? url.lastPathComponent : Self.normalize(name: url.lastPathComponent)
        let destination = LibraryPathResolver.uniqueDestination(for: finalName, in: documents)
        if isDirectory.boolValue {
            try FileManager.default.copyItem(at: url, to: destination)
        } else {
            // Координированное чтение — источник может быть в iCloud/на USB-C.
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: .forUploading, error: &coordinationError) { stagedURL in
                do { try FileManager.default.copyItem(at: stagedURL, to: destination) }
                catch { copyError = error }
            }
            if let copyError { throw copyError }
            if let coordinationError { throw coordinationError }
        }
        return destination
    }
}

/// Файл уже в библиотеке — это не ошибка, отдельный сигнал для баннера.
enum ImportSkipped: LocalizedError {
    case alreadyInLibrary(String)

    var errorDescription: String? {
        switch self {
        case .alreadyInLibrary(let name): return "«\(name)» уже добавлен."
        }
    }
}
