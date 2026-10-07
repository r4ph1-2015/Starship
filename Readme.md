Starship - Free and Open Source Forever

Download the dmg file through releases or website.

If you get a warning, Use these instructions

1. ```hdiutil attach ~/Downloads/Starship.dmg```

2. ```mkdir -p ~/Applications```

3. ```cp -R "/Volumes/Starship/Starship.app" ~/Applications/```

4. ```xattr -dr com.apple.quarantine ~/Applications/Starship.app```

5. ```codesign --force --deep --sign - ~/Applications/Starship.app```

6. ```codesign --verify --deep --strict --verbose=2 ~/Applications/Starship.app```

7. ```open ~/Applications/Starship.app```