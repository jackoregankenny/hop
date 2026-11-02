#!/bin/sh
# Builds build/Rayfast.app (launcher) and build/Tiles.app (tiling window manager).
# No dependencies beyond the Xcode command line tools.
#   ./build.sh                 build both
#   ./build.sh Tiles           build one
#   ./build.sh test            build both and run their self-tests
#   ./build.sh snaptest        press Rayfast's snap hotkeys on a throwaway Finder window and check
#                              where it lands (needs Accessibility; takes focus for a few seconds)
#   ./build.sh dist 0.3.0      release builds of both apps, zipped with checksums, in dist/
#   ./build.sh release 0.3.0   tag v0.3.0 and push; GitHub Actions builds and publishes the release
#
# Plain builds are version "dev" and never update themselves.
set -e
cd "$(dirname "$0")"

build() {
  APP=build/$1.app
  BIN=$APP/Contents/MacOS/$1
  mkdir -p "$APP/Contents/MacOS"
  cp "Sources/$1/Info.plist" "$APP/Contents/Info.plist"
  if [ -n "$VERSION" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" \
      "$APP/Contents/Info.plist"
  fi
  swiftc -swift-version 5 -Osize -wmo -target arm64-apple-macos13 -module-name "$1" \
    -Xlinker -dead_strip -o "$BIN" Sources/Shared/*.swift "Sources/$1"/*.swift
  strip -x "$BIN"
  codesign --force --sign - "$APP" >/dev/null 2>&1
  printf '%-8s %7s bytes\n' "$1" "$(stat -f %z "$BIN")"
}

case "$1" in
  test)
    build Rayfast && build Tiles
    build/Rayfast.app/Contents/MacOS/Rayfast --selftest | tail -1
    build/Tiles.app/Contents/MacOS/Tiles --selftest | tail -1 ;;
  snaptest)
    build Rayfast
    swiftc -O -o build/snaptest tests/snaptest.swift
    CFG=$(mktemp -d)   # empty config, so only the default hotkeys apply
    status=0
    build/snaptest build/Rayfast.app/Contents/MacOS/Rayfast "$CFG" || status=$?
    rmdir "$CFG"
    exit $status ;;
  dist)
    [ -n "$2" ] || { echo "usage: ./build.sh dist <version>"; exit 1; }
    VERSION=$2
    command rm -rf build dist
    build Rayfast && build Tiles
    mkdir -p dist
    for app in Rayfast Tiles; do
      ditto -c -k --keepParent "build/$app.app" "dist/$app.zip"
      shasum -a 256 "dist/$app.zip" | cut -d' ' -f1 > "dist/$app.zip.sha256"
    done
    ls -l dist ;;
  release)
    [ -n "$2" ] || { echo "usage: ./build.sh release <version>"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "commit your changes first"; exit 1; }
    git tag "v$2" && git push origin "v$2"
    echo "Tagged v$2; GitHub Actions is building the release." ;;
  "") build Rayfast && build Tiles ;;
  *) build "$1" ;;
esac
