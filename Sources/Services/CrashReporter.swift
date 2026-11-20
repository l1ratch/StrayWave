import Foundation

/// Записывает краш в файл журнала диагностики
/// (Application Support/StrayWave-debug.log): имя исключения или номер
/// сигнала плюс стек. Устанавливается один раз на старте приложения.
///
/// Best-effort: в signal-handler нельзя полноценно использовать Foundation,
/// поэтому запись минимальна — но её достаточно, чтобы увидеть тип падения
/// в «Ещё → Диагностика» после перезапуска.
enum CrashReporter {
    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let symbols = exception.callStackSymbols.prefix(24).joined(separator: "\n")
            CrashReporter.rawAppend("💥 EXC \(exception.name.rawValue): \(exception.reason ?? "-")\n\(symbols)")
        }
        let signals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP]
        for sig in signals {
            signal(sig) { code in
                CrashReporter.rawAppend("💥 сигнал \(code) (SIGABRT=6, SIGILL=4, SIGSEGV=11, SIGFPE=8, SIGBUS=7, SIGTRAP=5)")
                signal(code, SIG_DFL)
                raise(code)
            }
        }
    }

    /// Запись в обход DebugLog: обработчики вызываются в аварийном контексте,
    /// UIKit/SwiftUI трогать нельзя, только файл и fputs.
    private static func rawAppend(_ text: String) {
        // Тот же файл, что у DebugLog (Application Support, не Documents —
        // Documents наблюдается вотчером сканера).
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support.appendingPathComponent("StrayWave-debug.log")
        let stamped = "\n=== CRASH ===\n\(text)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(stamped.data(using: .utf8) ?? Data())
            try? handle.close()
        } else {
            try? stamped.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
