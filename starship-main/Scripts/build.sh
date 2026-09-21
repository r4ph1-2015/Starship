#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/build"
APP="$BUILD/Starship.app"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library \
  "$ROOT/Starship/main.swift" \
  "$ROOT/Starship/AppDelegate.swift" \
  "$ROOT/Starship/WallpaperEngine.swift" \
  "$ROOT/Starship/Library.swift" \
  "$ROOT/Starship/LockScreenManager.swift" \
  "$ROOT/Starship/TemporalEncoder.swift" \
  -framework AppKit -framework AVFoundation -framework VideoToolbox \
  -framework CoreMedia -framework CoreVideo -framework QuartzCore \
  -framework ServiceManagement \
  -o "$APP/Contents/MacOS/Starship"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Starship</string>
<key>CFBundleDisplayName</key><string>Starship</string>
<key>CFBundleIdentifier</key><string>com.starship.wallpaper</string>
<key>CFBundleExecutable</key><string>Starship</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>3.0.0</string>
<key>CFBundleVersion</key><string>300</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
(cd "$BUILD" && ditto -c -k --sequesterRsrc --keepParent Starship.app Starship.zip)
echo "Built: $APP"
echo "ZIP:   $BUILD/Starship.zip"
