#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/swift.sh build -c release --product MarauderNative
appPath="$PWD/dist/Marauder.app"
mkdir -p "$appPath/Contents/MacOS" "$appPath/Contents/Resources" .build/AppIcon.iconset
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift scripts/make-icon.swift "$PWD/.build/AppIcon.iconset"
python3 scripts/package-icon.py .build/AppIcon.iconset "$appPath/Contents/Resources/AppIcon.icns"
cp .build/release/MarauderNative "$appPath/Contents/MacOS/MarauderNative"
cp Resources/Info.plist "$appPath/Contents/Info.plist"
printf 'APPL????' > "$appPath/Contents/PkgInfo"
codesign --force --sign - "$appPath"
codesign --verify --deep --strict "$appPath"
plutil -lint "$appPath/Contents/Info.plist"
printf '\nBuilt %s\n' "$appPath"
