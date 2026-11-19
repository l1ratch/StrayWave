import Testing
import Foundation
@testable import StrayWave

@Suite("Относительные пути библиотеки")
struct PathResolverTests {
    private func makeDocuments() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrayWaveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Путь сохраняется относительным и восстанавливается в другом контейнере")
    func roundTripAcrossContainers() throws {
        let containerA = try makeDocuments()
        let containerB = try makeDocuments()
        let file = containerA.appendingPathComponent("Music/Rock/song.mp3")

        let relative = LibraryPathResolver.relativePath(for: file, in: containerA)
        #expect(relative == "Music/Rock/song.mp3")

        // «Обновление контейнера»: тот же относительный путь, другой корень.
        let restored = LibraryPathResolver.absoluteURL(for: relative!, in: containerB)
        #expect(restored?.path == containerB.appendingPathComponent("Music/Rock/song.mp3").path)
    }

    @Test("Файл вне Documents не получает относительный путь")
    func outsideDocuments() throws {
        let documents = try makeDocuments()
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("other.mp3")
        #expect(LibraryPathResolver.relativePath(for: outside, in: documents) == nil)
    }

    @Test("Траверсал «..» отклоняется")
    func traversalRejected() throws {
        let documents = try makeDocuments()
        #expect(LibraryPathResolver.absoluteURL(for: "../secret.txt", in: documents) == nil)
        #expect(LibraryPathResolver.absoluteURL(for: "", in: documents) == nil)
    }

    @Test("Одноимённые файлы копируются без перезаписи")
    func uniqueDestination() throws {
        let documents = try makeDocuments()
        FileManager.default.createFile(atPath: documents.appendingPathComponent("song.mp3").path, contents: Data())
        FileManager.default.createFile(atPath: documents.appendingPathComponent("song2.mp3").path, contents: Data())

        let destination = LibraryPathResolver.uniqueDestination(for: "song.mp3", in: documents)
        #expect(destination.lastPathComponent == "song3.mp3")
    }
}
