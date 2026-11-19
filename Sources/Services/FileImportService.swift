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
        } catch {
            banner = ImportBanner(title: "Ошибка импорта", message: error.localizedDescription)
        }
    }

    // MARK: - Импорт из «Файлов» → ссылка без копирования

    func importFromFiles(urls: [URL]) async {
        var linkedFiles = 0
        var skippedCopied = 0
        var failed = 0

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
            }
        }

        if failed > 0 {
            banner = ImportBanner(
                title: "Неподдерживаемый формат",
                message: "AVFoundation не умеет эти контейнеры. Поддерживаются: mp3, m4a, aac, flac, alac, wav, aiff, mp4, mov, m4v."
            )
        } else if skippedCopied > 0 {
            banner = ImportBanner(
                title: "Уже в библиотеке",
                message: "Файлы из папки StrayWave в «Файлах» добавляются автоматически — отдельно их импортировать не нужно."
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

    /// Возвращает false, если файл уже лежит в Documents (копия в библиотеке).
    private func saveBookmark(_ url: URL) throws -> Bool {
        guard LibraryPathResolver.relativePath(for: url) == nil else { return false }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        guard let container = AppEnvironment.shared.modelContainer else { return true }
        let context = ModelContext(container)
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

    private func copyIntoDocuments(_ url: URL) throws -> URL {
        let documents = LibraryPathResolver.documentsDirectory
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let destination = LibraryPathResolver.uniqueDestination(for: url.lastPathComponent, in: documents)
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
