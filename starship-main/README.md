# Starship — Native Swift macOS

A native Swift/AppKit rebuild of Starship. No Python, PyObjC, FFmpeg, Homebrew, or runtime Swift compilation.

## Features
- Menu bar `★`
- Import MP4/MOV/M4V wallpaper
- Full-screen animated desktop wallpaper on every display
- Infinite looping
- Starts at login using `SMAppService`
- Apply to macOS Tahoe Lock Screen using the existing Apple Aerial store
- Restore Apple Lock Screen
- Native AVFoundation + VideoToolbox encoding
- Visible Lock Screen progress

## Build
Run on macOS Tahoe with Xcode Command Line Tools installed:

```bash
cd Starship
./Scripts/build.sh
open build/Starship.app
```

The build creates `build/Starship.app` and `build/Starship.zip`.

The Lock Screen feature expects macOS Tahoe to have at least one downloaded Apple Aerial. Starship never downloads Apple assets itself.

## Build troubleshooting

If the build reports `failed to produce diagnostic for expression` in `LockScreenManager.swift` around `candidates.max`, this version already avoids that Swift compiler diagnostic by selecting the largest Aerial file with an explicit loop.
