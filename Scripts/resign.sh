#!/bin/bash
# Локальная переподпись неподписанного IPA вашим Ad-Hoc профилем.
# Запуск на macOS с установленным Xcode:
#
#   chmod +x Scripts/resign.sh
#   ./Scripts/resign.sh ClipDeck-unsigned.ipa profile.mobileprovision cert.p12 'P12_PASSWORD'
#
# Результат: ClipDeck-signed.ipa рядом с исходником.

set -euo pipefail

IPA="${1:?Укажите путь к ClipDeck-unsigned.ipa}"
PROFILE="${2:?Укажите .mobileprovision}"
P12="${3:?Укажите сертификат .p12}"
P12_PASSWORD="${4:?Укажите пароль .p12}"

WORK=$(mktemp -d)
KEYCHAIN="clipdeck-resign.$$"
KEYCHAIN_PASSWORD="$(openssl rand -hex 16)"
APP="$WORK/Payload/ClipDeck.app"

cleanup() {
    security delete-keychain "$KEYCHAIN" 2>/dev/null || true
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "→ Распаковка IPA"
unzip -q "$IPA" -d "$WORK"

echo "→ Импорт сертификата во временную связку ключей"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"' | tr '\n' ' ')

IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN" | awk -F'"' '/Apple Distribution|iPhone Distribution/ {print $2; exit}')
[ -n "$IDENTITY" ] || { echo "В .p12 нет Distribution-сертификата"; exit 1; }
echo "→ Подпись: $IDENTITY"

echo "→ Встраивание provisioning-профиля"
cp "$PROFILE" "$APP/embedded.mobileprovision"

# Entitlements берём ИЗ ПРОФИЛЯ — жёсткое совпадение с explicit-профилем.
security cms -D -i "$PROFILE" > "$WORK/profile.plist"
/usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$WORK/profile.plist" > "$WORK/entitlements.plist"
if ! /usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.kernel.increased-memory-limit" "$WORK/profile.plist" >/dev/null 2>&1; then
    echo "⚠ В профиле нет increased-memory-limit — уберите этот ключ и из Resources/ClipDeck.entitlements"
fi

echo "→ codesign"
codesign --force --sign "$IDENTITY" \
    --entitlements "$WORK/entitlements.plist" \
    --timestamp=none \
    "$APP"

codesign --verify --verbose "$APP"

echo "→ Упаковка ClipDeck-signed.ipa"
(cd "$WORK" && zip -q -r -y "$OLDPWD/ClipDeck-signed.ipa" Payload)
echo "Готово: ClipDeck-signed.ipa"
