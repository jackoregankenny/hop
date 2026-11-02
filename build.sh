#!/bin/sh
# Builds build/Hop.app. No dependencies beyond the Xcode command line tools.
#   ./build.sh                 dev build (includes the self-test and debug flags from tests/)
#   ./build.sh test            dev build, then run the self-test
#   ./build.sh snaptest        press Hop's snap hotkeys on a throwaway Finder window and check
#                              where it lands (needs Accessibility; takes focus for a few seconds)
#   ./build.sh dist 0.3.0      release build, zipped with a checksum, in dist/
#   ./build.sh release 0.3.0   tag v0.3.0 and push; GitHub Actions builds and publishes the release
#
# Dev builds are version "dev" and never update themselves; release builds (dist) ship only Sources/.
set -e
cd "$(dirname "$0")"

build() {
  APP=build/Hop.app
  BIN=$APP/Contents/MacOS/Hop
  mkdir -p "$APP/Contents/MacOS"
  cp Info.plist "$APP/Contents/Info.plist"
  if [ -n "$VERSION" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" \
      "$APP/Contents/Info.plist"
  fi
  # Dev builds also compile tests/ (self-test, --probe, --snapshot); release builds ship only Sources/.
  if [ -n "$VERSION" ]; then EXTRA=""; else EXTRA="-D TESTING tests/SelfTest.swift tests/Debug.swift"; fi
  # shellcheck disable=SC2086
  swiftc -swift-version 5 -Osize -wmo -target arm64-apple-macos13 -module-name Hop \
    -Xlinker -dead_strip -o "$BIN" Sources/*.swift $EXTRA
  strip -x "$BIN"
  codesign --force --sign - "$APP" >/dev/null 2>&1
  printf 'Hop %7s bytes\n' "$(stat -f %z "$BIN")"
}

case "$1" in
  test)
    build
    build/Hop.app/Contents/MacOS/Hop --selftest | tail -1 ;;
  snaptest)
    build
    swiftc -O -o build/snaptest tests/snaptest.swift
    CFG=$(mktemp -d)   # empty config, so only the default hotkeys apply
    status=0
    build/snaptest build/Hop.app/Contents/MacOS/Hop "$CFG" || status=$?
    rmdir "$CFG"
    exit $status ;;
  dist)
    [ -n "$2" ] || { echo "usage: ./build.sh dist <version>"; exit 1; }
    VERSION=$2
    command rm -rf build dist
    build
    mkdir -p dist
    ditto -c -k --keepParent build/Hop.app dist/Hop.zip
    shasum -a 256 dist/Hop.zip | cut -d' ' -f1 > dist/Hop.zip.sha256
    ls -l dist ;;
  release)
    [ -n "$2" ] || { echo "usage: ./build.sh release <version>"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "commit your changes first"; exit 1; }
    git tag "v$2" && git push origin "v$2"
    echo "Tagged v$2; GitHub Actions is building the release." ;;
  "") build ;;
  *) echo "unknown command: $1"; exit 1 ;;
esac
