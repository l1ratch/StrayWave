import Foundation
import Observation

/// Журнал диагностики, видимый в «Ещё → Диагностика».
///
/// Записи ПЕРСИСТЯТСЯ в файл Documents/StrayWave-debug.log: журнал должен
/// переживать краш (главный сценарий — воспроизвести падение, открыть
/// диагностику и отправить лог). Хвост файла ~256 КБ.
///
/// Класс nonisolated + NSLock: в журнал пишут и главный поток (пикер,
/// NowPlaying), и actor-сканер — изоляция MainActor не подходит.
@Observable
final class DebugLog {
    static let shared = DebugLog()

    private static let fileURL: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("StrayWave-debug.log")
    }()

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let maxFileBytes = 256 * 1024
    private static let maxEntries = 300

    private let lock = NSLock()
    private var storage: [String] = []

    private init() {
        loadLocked()
    }

    nonisolated func add(_ message: String) {
        let line = "\(Self.stamp.string(from: .now))  \(message)"
        lock.lock()
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
