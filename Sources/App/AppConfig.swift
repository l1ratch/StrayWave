import Foundation

/// Глобальные константы конфигурации.
///
/// В Swift-коде НЕ храним Team ID и application-identifier: неподписанный IPA
/// переподписывается на устройстве через GBox, который сам подставляет
/// application-identifier из .mobileprovision. Bundle ID приложения
/// (com.l1ratch.StrayWave) задаётся только в project.yml.
enum AppConfig {
    /// App Group из доступного списка профиля (…1 … …5).
    /// Меняется только последняя цифра при необходимости.
    ///
    /// Сейчас НЕ используется: приложение однотаргетное, без расширений,
    /// все данные лежат в стандартных Documents / Library/Caches.
    /// Понадобится только для общего контейнера с расширениями
    /// (UserDefaults(suiteName:) / общий SwiftData store) — тогда же
    /// добавить com.apple.security.application-groups в entitlements.
    static let appGroupID = "group.c2fefdd0db2e255e.5"
}
