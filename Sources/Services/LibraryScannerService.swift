import Foundation
import Darwin
import AVFoundation
import SwiftData

/// Снимок записи библиотеки, передаваемый сканеру (без SwiftData-объектов).
struct KnownLibraryRecord: Sendable {
    let id: UUID
    let storageRaw: String
    let relativePath: String?
    let bookmarkData: Data?
    let fingerprint: FileFingerprint?
}

/// Результат чтения одного файла.
struct ScannedMedia: Sendable {
    let existingID: UUID?
    let sourceURL: URL
    let kind: MediaKind
    let storageType: MediaStorageType
    let title: String
    let artist: String?
    let album: String?
    let duration: TimeInterval
    let videoWidth: Int?
    let videoHeight: Int?
    let fileSize: Int64
    let modificationDate: Date?
    let artworkFileName: String?
}

struct ScanOutcome: Sendable {
    var items: [ScannedMedia] = []
    /// Записи, не изменившиеся с прошлого сканирования, — не трогаем и не удаляем.
    var retainedItemIDs: Set<UUID> = []
    /// Локальные пути, подтверждённые на диске.
    var presentRelativePaths: Set<String> = []
    /// Просроченные/недоступные bookmark-ссылки.
    var lostBookmarkIDs: Set<UUID> = []
    var unsupportedFileNames: [String] = []
}

/// Фоновый сканер Documents + security-scoped bookmark-ссылок.
///
/// Вся работа с ФС и AVURLAsset выполняется в actor — MainActor не блокируется.
actor LibraryScannerService {
    private let artwork = ArtworkCacheService.shared
    private var directoryWatcher: DispatchSourceFileSystemObject?
    /// Отпечатки уже прочитанных файлов: повторные сканирования не дёргают AVURLAsset.
    private var fingerprintCache: [String: FileFingerprint] = [:]

    // MARK: - Сканирование

    func scan(documents: URL, known: [KnownLibraryRecord]) async -> ScanOutcome {
        var outcome = ScanOutcome()
        let knownByPath = Dictionary(
            known.compactMap { record -> (String, KnownLibraryRecord)? in
                guard let path = record.relativePath else { return nil }
                return (path, record)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let fileManager = FileManager.default
        var fileURLs: [URL] = []
        if let enumerator = fileManager.enumerator(
            at: documents,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            // nextObject() вместо for-in: итератор DirectoryEnumerator
            // недоступен из асинхронного контекста (Swift 6).
            while let url = enumerator.nextObject() as? URL {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                fileURLs.append(url)
            }
        }
        fileURLs = ScannerSupport.dedupe(fileURLs)

        for url in fileURLs {
            guard let relativePath = LibraryPathResolver.relativePath(for: url, in: documents) else { continue }
            if let kind = SupportedFormats.kind(for: url) {
                outcome.presentRelativePaths.insert(relativePath)
                let fingerprint = FileFingerprint(url: url)
                let record = knownByPath[relativePath]
                let cacheKey = url.standardizedFileURL.path.lowercased()
                let previous = fingerprintCache[cacheKey] ?? record?.fingerprint
                if let record, !ScannerSupport.needsReimport(old: previous, new: fingerprint) {
                    outcome.retainedItemIDs.insert(record.id)
                    continue
                }
                let scanned = await scanFile(
                    url: url, kind: kind, storage: .localDocuments,
                    existingID: record?.id, artworkID: record?.id ?? UUID()
                )
                outcome.items.append(scanned)
            } else if SupportedFormats.isUnsupportedMedia(url) {
                outcome.unsupportedFileNames.append(url.lastPathComponent)
            }
        }

        for record in known where record.storageRaw == MediaStorageType.securityBookmark.rawValue {
            guard let data = record.bookmarkData else {
                outcome.lostBookmarkIDs.insert(record.id)
                continue
            }
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale),
                  url.startAccessingSecurityScopedResource() else {
                outcome.lostBookmarkIDs.insert(record.id)
                continue
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard FileManager.default.fileExists(atPath: url.path) else {
                outcome.lostBookmarkIDs.insert(record.id)
                continue
            }
            let fingerprint = FileFingerprint(url: url)
            let cacheKey = "bookmark:\(record.id.uuidString)"
            let previous = fingerprintCache[cacheKey] ?? record.fingerprint
            if !ScannerSupport.needsReimport(old: previous, new: fingerprint) {
                outcome.retainedItemIDs.insert(record.id)
                continue
            }
            let kind = SupportedFormats.kind(for: url) ?? .audio
            let scanned = await scanFile(
                url: url, kind: kind, storage: .securityBookmark,
                existingID: record.id, artworkID: record.id
            )
            outcome.items.append(scanned)
        }

        return outcome
    }

    // MARK: - Наблюдение за папкой Documents

    func startWatching(documents: URL, onChange: @escaping @Sendable () -> Void) {
        guard directoryWatcher == nil else { return }
        let descriptor = open(documents.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .global(qos: .utility)
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { [descriptor] in close(descriptor) }
        source.resume()
        directoryWatcher = source
    }

    func stopWatching() {
        directoryWatcher?.cancel()
        directoryWatcher = nil
    }

    deinit {
        directoryWatcher?.cancel()
    }

    // MARK: - Private

    private func scanFile(
        url: URL, kind: MediaKind, storage: MediaStorageType,
        existingID: UUID?, artworkID: UUID
    ) async -> ScannedMedia {
        let asset = AVURLAsset(url: url)
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        let duration = (try? await asset.load(.duration)) ?? .zero
        let title = Self.metadataString(metadata, key: .commonKeyTitle)
            ?? url.deletingPathExtension().lastPathComponent
        let artist = Self.metadataString(metadata, key: .commonKeyArtist)
        let album = Self.metadataString(metadata, key: .commonKeyAlbumName)

        var width: Int?
        var height: Int?
        if kind == .video, let tracks = try? await asset.load(.tracks) {
            for track in tracks where track.mediaType == .video {
                if let size = try? await track.load(.naturalSize) {
                    width = Int(abs(size.width))
                    height = Int(abs(size.height))
                }
                break
            }
        }

        let artworkFileName = await artwork.prepareArtwork(for: url, kind: kind, itemID: artworkID)
        let fingerprint = FileFingerprint(url: url)
        if let fingerprint {
            fingerprintCache[url.standardizedFileURL.path.lowercased()] = fingerprint
            if let existingID { fingerprintCache["bookmark:\(existingID.uuidString)"] = fingerprint }
        }
        return ScannedMedia(
            existingID: existingID,
            sourceURL: url,
            kind: kind,
            storageType: storage,
            title: title,
            artist: artist,
            album: album,
            duration: duration.isNumeric ? max(0, duration.seconds) : 0,
            videoWidth: width,
            videoHeight: height,
            fileSize: fingerprint?.size ?? 0,
            modificationDate: fingerprint?.modificationDate,
            artworkFileName: artworkFileName
        )
    }

    private static func metadataString(_ metadata: [AVMetadataItem], key: AVMetadataKey) -> String? {
        for item in AVMetadataItem.metadataItems(from: metadata, withKey: key.rawValue, keySpace: .common) {
            if let value = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

/// Применение результатов сканирования к SwiftData. Только MainActor.
@MainActor
enum LibrarySync {
    /// Возвращает ID удалённых записей (для очистки Spotlight).
    @discardableResult
    static func apply(_ outcome: ScanOutcome, context: ModelContext) -> [UUID] {
        var deletedIDs: [UUID] = []
        let documents = LibraryPathResolver.documentsDirectory
        let existing = (try? context.fetch(FetchDescriptor<MediaItem>())) ?? []
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let existingByPath = Dictionary(
            existing.compactMap { item -> (String, MediaItem)? in
                guard let path = item.relativePath else { return nil }
                return (path, item)
            },
            uniquingKeysWith: { first, _ in first }
        )

        for scanned in outcome.items {
            let relativePath = scanned.storageType == .localDocuments
                ? LibraryPathResolver.relativePath(for: scanned.sourceURL, in: documents)
                : nil
            let item = scanned.existingID.flatMap { existingByID[$0] }
                ?? relativePath.flatMap { existingByPath[$0] }
            if let item {
                item.title = scanned.title
                item.artist = scanned.artist
                item.album = scanned.album
                item.duration = scanned.duration
                item.fileSize = scanned.fileSize
                if let artwork = scanned.artworkFileName { item.artworkFileName = artwork }
            } else {
                let item = MediaItem(
                    kind: scanned.kind,
                    storageType: scanned.storageType,
                    relativePath: relativePath,
                    bookmarkData: nil,
                    title: scanned.title,
                    artist: scanned.artist,
                    album: scanned.album,
                    duration: scanned.duration,
                    fileSize: scanned.fileSize,
                    artworkFileName: scanned.artworkFileName
                )
                context.insert(item)
            }
        }

        for item in existing {
            switch item.storageType {
            case .localDocuments:
                guard let path = item.relativePath else { continue }
                if !outcome.presentRelativePaths.contains(path) {
                    deletedIDs.append(item.id)
                    context.delete(item)
                }
            case .securityBookmark:
                if outcome.lostBookmarkIDs.contains(item.id) {
                    deletedIDs.append(item.id)
                    context.delete(item)
                }
            }
        }

        try? context.save()
        return deletedIDs
    }
}
