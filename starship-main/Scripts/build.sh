#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/build"
APP="$BUILD/starship.app"
STARSHIP_SDK="${STARSHIP_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
if [[ ! -d "$STARSHIP_SDK" ]]; then STARSHIP_SDK="$(xcrun --sdk macosx --show-sdk-path)"; fi
rm -rf "$BUILD/Starship.app" "$APP"
rm -f "$BUILD/Starship.zip" "$BUILD/starship.dmg"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library \
  -target arm64-apple-macosx26.0 \
  -sdk "$STARSHIP_SDK" \
  "$ROOT/Starship/main.swift" \
  "$ROOT/Starship/AppDelegate.swift" \
  "$ROOT/Starship/GalleryCatalog.swift" \
  "$ROOT/Starship/WallpaperEngine.swift" \
  "$ROOT/Starship/Library.swift" \
  -framework AppKit -framework AVKit -framework AVFoundation -framework VideoToolbox \
  -framework CoreMedia -framework CoreVideo -framework QuartzCore \
  -o "$APP/Contents/MacOS/Starship"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Starship Snowflake</string>
<key>CFBundleDisplayName</key><string>Starship Snowflake</string>
<key>CFBundleIdentifier</key><string>com.starship.wallpaper</string>
<key>CFBundleExecutable</key><string>Starship</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>2026.1</string>
<key>CFBundleVersion</key><string>202601</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
hdiutil create -volname "Starship Snowflake 2026.1" -srcfolder "$APP" -ov -format UDZO "$BUILD/starship.dmg"
echo "Built: $APP"
echo "DMG:   $BUILD/starship.dmg"
