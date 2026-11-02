#!/bin/sh
# Builds build/Hop.app. No dependencies beyond the Xcode command line tools.
#   ./build.sh                 dev build (includes the self-test and debug flags from tests/)
#   ./build.sh test            dev build, then run the self-test
#   ./build.sh snaptest        press Hop's snap hotkeys on a throwaway Finder window and check
#                              where it lands (needs Accessibility; takes focus for a few seconds)
#   ./build.sh dist 0.3.0      release build, signed and notarized, zipped with a checksum, in dist/
#   ./build.sh release 0.3.0   dist, then tag v0.3.0 and publish the GitHub Release from this Mac
#
# Dev builds are version "dev", ad-hoc signed, and never update themselves; release builds (dist) ship
# only Sources/. Releases are signed with the Developer ID in this Mac's keychain (or $HOP_SIGN), so the
# signature, and with it the Accessibility permission, stays the same from one version to the next.
# They are built here rather than in CI so that key never leaves this Mac. Notarization runs when the
# keychain has a notarytool profile named hop-notary (or $HOP_NOTARY); create it once with
#   xcrun notarytool store-credentials hop-notary --apple-id <you> --team-id <team>
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
  if [ -n "$VERSION" ]; then
    codesign --force --options runtime --timestamp --entitlements Hop.entitlements --sign "$SIGN" "$APP"
  else
    codesign --force --sign - "$APP" >/dev/null 2>&1
  fi
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
    SIGN=${HOP_SIGN:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)}
    [ -n "$SIGN" ] || { echo "no Developer ID Application identity in the keychain (or set HOP_SIGN)"; exit 1; }
    command rm -rf build dist
    build
    codesign --verify --strict build/Hop.app
    mkdir -p dist
    NOTARY=${HOP_NOTARY:-hop-notary}
    if xcrun notarytool history --keychain-profile "$NOTARY" >/dev/null 2>&1; then
      ditto -c -k --keepParent build/Hop.app dist/Hop.zip
      xcrun notarytool submit dist/Hop.zip --keychain-profile "$NOTARY" --wait
      xcrun stapler staple build/Hop.app
      command rm dist/Hop.zip
    else
      echo "note: not notarized (no notarytool profile \"$NOTARY\"); updates are fine, a fresh download warns once"
    fi
    ditto -c -k --keepParent build/Hop.app dist/Hop.zip
    shasum -a 256 dist/Hop.zip | cut -d' ' -f1 > dist/Hop.zip.sha256
    echo "signed: $SIGN"
    ls -l dist ;;
  release)
    [ -n "$2" ] || { echo "usage: ./build.sh release <version>"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "commit your changes first"; exit 1; }
    "$0" test
    "$0" dist "$2"
    git push origin HEAD
    git tag "v$2" && git push origin "v$2"
    gh release create "v$2" dist/Hop.zip dist/Hop.zip.sha256 --title "v$2" --generate-notes
    echo "Published v$2." ;;
  "") build ;;
  *) echo "unknown command: $1"; exit 1 ;;
esac
