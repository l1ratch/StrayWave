import Testing
import Foundation
@testable import StrayWave

@Suite("Дедупликация сканера")
struct ScannerDedupTests {
    @Test("Дубликаты по нормализованному пути схлопываются")
    func dedupePaths() {
        let a = URL(fileURLWithPath: "/Library/Documents/song.mp3")
        let variants = [
            URL(fileURLWithPath: "/Library/Documents/song.mp3"),
            URL(fileURLWithPath: "/Library/Documents/SONG.MP3"),
            URL(fileURLWithPath: "/Library/Documents/../Documents/song.mp3")
        ]
        let result = ScannerSupport.dedupe([a] + variants)
        #expect(result.count == 1)
        #expect(result.first == a)
    }

    @Test("Разные файлы не схлопываются")
    func distinctFilesSurvive() {
        let urls = [
            URL(fileURLWithPath: "/docs/a.mp3"),
            URL(fileURLWithPath: "/docs/b.mp3"),
            URL(fileURLWithPath: "/docs/sub/a.mp3")
        ]
        #expect(ScannerSupport.dedupe(urls).count == 3)
    }

    @Test("Одинаковый отпечаток — повторный импорт не нужен")
    func unchangedFingerprint() {
        let date = Date()
        let old = FileFingerprint(size: 100, modificationDate: date)
        let new = FileFingerprint(size: 100, modificationDate: date)
        #expect(!ScannerSupport.needsReimport(old: old, new: new))
    }

    @Test("Изменение размера или даты требует повторного чтения метаданных")
    func changedFingerprint() {
        let date = Date()
        let old = FileFingerprint(size: 100, modificationDate: date)
        #expect(ScannerSupport.needsReimport(old: old, new: FileFingerprint(size: 200, modificationDate: date)))
        #expect(ScannerSupport.needsReimport(old: old, new: FileFingerprint(size: 100, modificationDate: date.addingTimeInterval(60))))
    }

    @Test("Неподдерживаемые контейнеры классифицируются без краша")
    func unsupportedFormats() {
        #expect(SupportedFormats.kind(for: URL(fileURLWithPath: "/x/movie.mkv")) == nil)
        #expect(SupportedFormats.isUnsupportedMedia(URL(fileURLWithPath: "/x/movie.webm")))
        #expect(SupportedFormats.kind(for: URL(fileURLWithPath: "/x/track.flac")) == .audio)
        #expect(SupportedFormats.kind(for: URL(fileURLWithPath: "/x/clip.MOV")) == .video)
        // Прочие файлы (не медиа) просто игнорируются сканером.
        #expect(!SupportedFormats.isUnsupportedMedia(URL(fileURLWithPath: "/x/readme.txt")))
    }
}
