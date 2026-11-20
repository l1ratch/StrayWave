import Foundation

/// Журнал диагностики, видимый в «Ещё → Диагностика».
///
/// ВАЖНО: файл живёт в Application Support, НЕ в Documents — Documents
/// наблюдается DispatchSource- вотчером сканера, и записи журнала туда
/// вызывали бесконечный перескан (запись лога → вотчер → скан → запись
/// лога о скане → …), что и давало постоянные «🗂 LibrarySync» в простое.
///
/// Класс nonisolated + NSLock: пишут и главный поток, и actor-сканер.
/// @Observable НЕ используется: registrar наблюдателя не потокобезопасен,
/// конкурентный доступ к нему из двух потоков ронял приложение (SIGTRAP).
final class DebugLog: @unchecked Sendable {
    static let shared = DebugLog()

    private static let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("StrayWave-debug.log")
    }()

    // Доступ строго под lock.
    private nonisolated(unsafe) static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let maxFileBytes = 256 * 1024
    private static let maxEntries = 400

    private let lock = NSLock()
    private var storage: [String] = []

    private init() {
        loadLocked()
    }

    nonisolated func add(_ message: String) {
        lock.lock()
        let line = "\(Self.stamp.string(from: .now))  \(message)"
        storage.append(line)
        if storage.count > Self.maxEntries { storage.removeFirst(storage.count - Self.maxEntries) }
        appendToFileLocked(line)
        lock.unlock()
    }

    nonisolated func clear() {
        lock.lock()
        storage.removeAll()
        try? FileManager.default.removeItem(at: Self.fileURL)
        lock.unlock()
    }

    nonisolated var text: String {
        lock.lock()
        defer { lock.unlock() }
        return storage.joined(separator: "\n")
    }

    // MARK: - Private (вызывать только под lock)

    private func loadLocked() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let content = String(data: data, encoding: .utf8) else { return }
        storage = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if storage.count > Self.maxEntries { storage.removeFirst(storage.count - Self.maxEntries) }
    }

    private func appendToFileLocked(_ line: String) {
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: Self.fileURL.path),
           let size = attrs[.size] as? Int, size > Self.maxFileBytes {
            try? (storage.joined(separator: "\n") + "\n").write(to: Self.fileURL, atomically: true, encoding: .utf8)
            return
        }
        if let handle = try? FileHandle(forWritingTo: Self.fileURL) {
            handle.seekToEndOfFile()
            handle.write((line + "\n").data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            try? (line + "\n").write(to: Self.fileURL, atomically: true, encoding: .utf8)
        }
    }
}
