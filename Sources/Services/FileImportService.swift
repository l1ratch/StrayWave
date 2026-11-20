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

    // MARK: - Импорт из «Файлов» (asCopy: true → копия в Documents)

    func importFromFiles(urls: [URL]) async {
        // Диагностика цепочки по журналам видна в «Ещё → Диагностика».
        banner = ImportBanner(title: "Импорт из «Файлов»", message: "Выбрано: \(urls.count). Копирую…")
        DebugLog.shared.add("📥 importFromFiles: \(urls.count) URL")

        var copiedFiles = 0
        var skipped = 0
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
                        do {
                            _ = try copyIntoDocuments(file)
                            copiedFiles += 1
                        } catch let skip as ImportSkipped {
                            skipped += 1
                        } catch {
                            failed += 1
                            if firstError == nil { firstError = error.localizedDescription }
                        }
                    }
                } else if SupportedFormats.isUnsupportedMedia(url) {
                    failed += 1
                    DebugLog.shared.add("⚠️ пропуск (неподдерживаемый): \(url.lastPathComponent)")
                } else if SupportedFormats.kind(for: url) == nil {
                    DebugLog.shared.add("⚠️ пропуск (kind == nil): \(url.lastPathComponent)")
                    continue
                } else {
                    do {
                        _ = try copyIntoDocuments(url)
                        copiedFiles += 1
                        DebugLog.shared.add("✅ скопирован: \(url.lastPathComponent)")
                    } catch let skip as ImportSkipped {
                        skipped += 1
                        DebugLog.shared.add("↩️ пропуск (уже есть): \(url.lastPathComponent)")
                    }
                }
            } catch {
                failed += 1
                if firstError == nil { firstError = error.localizedDescription }
                DebugLog.shared.add("❌ ошибка по \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        DebugLog.shared.add("📊 итог: скопировано \(copiedFiles), пропущено \(skipped), ошибок \(failed)")

        if failed > 0 {
            banner = ImportBanner(
                title: "Ошибка импорта",
                message: firstError ?? "AVFoundation не умеет эти контейнеры. Поддерживаются: mp3, m4a, aac, flac, alac, wav, aiff, mp4, mov, m4v."
            )
        } else if skipped > 0 && copiedFiles == 0 {
            banner = ImportBanner(
                title: "Уже в библиотеке",
                message: "Эти файлы уже добавлены — копии не созданы."
            )
        } else if copiedFiles > 0 {
            banner = ImportBanner(
                title: "Добавлено в библиотеку",
                message: "Скопировано файлов: \(copiedFiles). Сканер подхватит их автоматически."
            )
        }
        if copiedFiles > 0 { await AppEnvironment.shared.rescanLibrary() }
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
    // (saveBookmark удалён: в среде GBox asCopy:false всегда завершался
    // «отменой» — подтверждено журналом диагностики. Импорт из «Файлов»
    // переведён на копирование, как и «Поделиться».)

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
