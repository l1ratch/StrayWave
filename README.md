# ClipDeck

Минималистичный полностью оффлайн аудио-/видеоплеер для iOS 27. Ноль внешних зависимостей, один таргет, Swift 6 (strict concurrency), SwiftUI + Liquid Glass, SwiftData, AVFoundation.

## Сборка

```bash
brew install xcodegen
xcodegen generate

# Симулятор
xcodebuild -project ClipDeck.xcodeproj -scheme ClipDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Неподписанный device-билд для последующей переподписи
xcodebuild -project ClipDeck.xcodeproj -scheme ClipDeck \
  -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

Или запустите workflow **Build ClipDeck IPA** в GitHub Actions — заберите артефакт `ClipDeck-unsigned.ipa`.

## Подпись (Ad-Hoc, explicit App ID `app.yam53.taro5888`)

Профиль привязан к UDID устройств, поэтому рекомендованная схема — **CI отдаёт неподписанный IPA, подпись выполняется локально**:

```bash
chmod +x Scripts/resign.sh
./Scripts/resign.sh ClipDeck-unsigned.ipa ClipDeck.mobileprovision Certificate.p12 'пароль-p12'
```

Скрипт берёт entitlements прямо из `.mobileprovision` (гарантированное совпадение с профилем), встраивает `embedded.mobileprovision` и подписывает Distribution-сертификатом. Альтернатива без Mac — GBox/AltStore на самом устройстве, как в WSBridge-iOS.

В проекте ровно один app-таргет (без `.appex`), entitlements ограничены `increased-memory-limit` и `siri`, CarPlay/iCloud не используются.

## Тесты

```bash
xcodebuild -project ClipDeck.xcodeproj -scheme ClipDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Swift Testing: логика очереди (shuffle/repeat/перестановка), относительные пути с «сменой контейнера», дедупликация сканера и классификация неподдерживаемых форматов.

## Как пользоваться

- **Файлы → На iPhone → ClipDeck**: всё, что сюда скопировано (Finder/AirDrop/USB-C), появляется в библиотеке автоматически — сканер следит за папкой.
- **«Открыть в…»** из любого приложения: файл копируется в библиотеку без перезаписи одноимённых.
- **«+» в «Музыке»**: копирование либо ссылка (Security-Scoped Bookmark) для тяжёлых видео на внешнем носителе.
- **Spotlight**: файлы ищутся на рабочем столе, тап сразу запускает воспроизведение.
- **Siri / Команды**: `PlayMediaIntent`, `PlayPlaylistIntent` (например, автозапуск плейлиста по Bluetooth), `TogglePlaybackIntent`, `NextTrackIntent` — всё внутри основного таргета.

## Замечание по API iOS 27

Модификаторы `.reorderable()` / `.reorderContainer` / `.swipeActionsContainer()` из ТЗ заменены на нативные `List` + `.onMove` + `.swipeActions`: это тот же системный UX перетаскивания и свайпов, но код компилируется на текущем SDK без угадывания сигнатур. Когда Xcode 27 SDK подтвердит новые модификаторы, заменить их нужно только в `QueueSheetView` и `PlaylistDetailView`. Liquid Glass-навигация (`Tab`, `.tabBarMinimizeBehavior`, `.tabViewBottomAccessory`, zoom-переход) используется как задано.
