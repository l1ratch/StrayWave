import Foundation
import SwiftUI

/// Режим встроенного импорта из меню «+».
enum ImportMode: String, Sendable {
    case copy
    case bookmark

    var title: String {
        switch self {
        case .copy: return "Копировать в библиотеку"
        case .bookmark: return "Добавить ссылкой (без копирования)"
        }
    }

    var systemImage: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .bookmark: return "link"
        }
    }
}

/// Одноразовое сообщение-баннер (ошибка формата, неподдерживаемый контейнер).
struct ImportBanner: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let message: String
}

/// Импорт файлов: системное «Открыть в…», `.fileImporter` (копия / bookmark).
@MainActor @Observable
final class FileImportService {
    var banner: ImportBanner?

    // MARK: - «Открыть в…» из других приложений

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

    // MARK: - Встроенный fileImporter

    func importURLs(_ urls: [URL], mode: ImportMode) async {
        var copied = 0
        var linked = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                switch mode {
                case .copy:
                    _ = try copyIntoDocuments(url)
                    copied += 1
                case .bookmark:
                    try saveBookmark(url)
                    linked += 1
                }
            } catch {
                banner = ImportBanner(title: "Ошибка импорта", message: error.localizedDescription)
            }
        }
        if copied + linked > 0 { await AppEnvironment.shared.rescanLibrary() }
    }

    // MARK: - Private

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

    private func saveBookmark(_ url: URL) throws {
        guard SupportedFormats.kind(for: url) != nil else {
            banner = ImportBanner(
                title: "Неподдерживаемый формат",
                message: "«\(url.lastPathComponent)» нельзя открыть через AVFoundation."
            )
            return
        }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        guard let container = AppEnvironment.shared.modelContainer else { return }
        let context = ModelContext(container)
        let item = MediaItem(
            kind: SupportedFormats.kind(for: url) ?? .audio,
            storageType: .securityBookmark,
            bookmarkData: data,
            title: url.deletingPathExtension().lastPathComponent
        )
        context.insert(item)
        try context.save()
    }
}
