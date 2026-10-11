#!/bin/bash
# Builds ClawdPet.app (universal: Apple silicon + Intel) with the Xcode command line tools.
# Run on a Mac:  bash mac/build.sh   ->  mac/build/ClawdPet.app and mac/build/ClawdPet-mac.zip
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build
mkdir -p build

FLAGS="-O -swift-version 5 -framework Cocoa"
swiftc $FLAGS -target arm64-apple-macos12.0 main.swift -o build/ClawdPet-arm64
swiftc $FLAGS -target x86_64-apple-macos12.0 main.swift -o build/ClawdPet-x86_64
lipo -create build/ClawdPet-arm64 build/ClawdPet-x86_64 -output build/ClawdPet-bin

APP=build/ClawdPet.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/ClawdPet-bin "$APP/Contents/MacOS/ClawdPet"
cp Info.plist "$APP/Contents/Info.plist"

# The app draws its own icon; turn that picture into an .icns
build/ClawdPet-bin --icon build/icon.png
mkdir -p build/AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d build/icon.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: needed so the app starts at all on Apple silicon
codesign --force --deep --sign - "$APP"
(cd build && ditto -c -k --keepParent ClawdPet.app ClawdPet-mac.zip)
echo "Done: mac/$APP"
