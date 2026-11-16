#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cp resources/BMusic.svg Sources/BMusic/Resources/BMusic.svg
ICON_TEMP="$(mktemp -d)"
trap 'rm -rf "$ICON_TEMP"' EXIT
ICON_WORK="$ICON_TEMP/BMusic.iconset"
swift scripts/make-icon.swift "$ICON_WORK"
iconutil -c icns "$ICON_WORK" -o resources/AppIcon.icns
# CLT SwiftPM can stamp the deployment target as the linked SDK version.
# Pass the actual SDK to ld so AppKit selects the current native appearance.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
swift build -c release -Xlinker -rpath -Xlinker @executable_path/../Frameworks -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK_VERSION"
APP="$PWD/dist/BMusic.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/BMusic" "$APP/Contents/MacOS/BMusic"
cp resources/BMusic.svg "$APP/Contents/Resources/BMusic.svg"
cp resources/Info.plist "$APP/Contents/Info.plist"
cp resources/AppIcon.icns "$APP/Contents/Resources/BMusicIcon.icns"
mkdir -p "$APP/Contents/Frameworks"
SPARKLE_FRAMEWORK="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
rm -f "$APP/Contents/Resources/AppIcon.icns"
# Keep local debug paths out of distributed binaries.
strip -S "$APP/Contents/MacOS/BMusic"
codesign --force --deep --sign - "$APP"
printf 'Built %s\n' "$APP"
