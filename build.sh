#!/bin/bash
# ./build.sh            build HeyDay.app for this Mac
# ./build.sh install    build, copy to ~/Applications, launch
# ./build.sh release    universal, Developer ID signed + notarized build/HeyDay.zip
# PUBLISH=1 VERSION=v0.2.0 ./build.sh release    ...then tag, push and create the GitHub release
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || echo v0.0.0)}"
VERSION="${VERSION#v}"
ARCHS=$(uname -m)
[[ "${1:-}" == "release" ]] && ARCHS="arm64 x86_64"

APP=build/HeyDay.app
rm -rf "$APP" build/HeyDay-* build/HeyDay.zip
mkdir -p "$APP/Contents/MacOS"

for arch in $ARCHS; do
  swiftc -O -enable-bare-slash-regex -target "$arch-apple-macos13" \
    Sources/HeyDay.swift -o "build/HeyDay-$arch" 2>&1 | grep -v "^$" || true
  test -x "build/HeyDay-$arch"
done
lipo -create build/HeyDay-* -output "$APP/Contents/MacOS/HeyDay"
rm build/HeyDay-*

cat >"$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.rock.heyday</string>
  <key>CFBundleName</key><string>HeyDay</string>
  <key>CFBundleExecutable</key><string>HeyDay</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
if [[ "${1:-}" == "release" ]]; then
  # Developer ID + hardened runtime + secure timestamp: what notarization requires.
  SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application[^"]*"' | head -1 | tr -d '"')}"
  [[ -n "$SIGN_ID" ]] || { echo "no Developer ID Application identity in keychain" >&2; exit 1; }
  codesign --force --options runtime --timestamp -s "$SIGN_ID" "$APP"
else
  codesign -s - --force "$APP" >/dev/null
fi
echo "built $APP ($VERSION, $ARCHS)"

case "${1:-}" in
  install)
    mkdir -p ~/Applications
    pkill -x HeyDay || true
    rm -rf ~/Applications/HeyDay.app && cp -R "$APP" ~/Applications/
    # The app registers itself as a login item now; drop the old AppleScript one.
    osascript -e 'tell application "System Events" to delete (every login item whose name is "HeyDay")' >/dev/null 2>&1 || true
    open ~/Applications/HeyDay.app
    echo "installed to ~/Applications"
    ;;
  release)
    # Notary auth: App Store Connect API key via env (CI), else a stored keychain profile.
    if [[ -n "${NOTARY_KEY:-}" ]]; then
      AUTH=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
    else
      AUTH=(--keychain-profile "${NOTARY_PROFILE:-heyday-notary}")
    fi
    ditto -c -k --keepParent "$APP" build/HeyDay.zip
    xcrun notarytool submit build/HeyDay.zip "${AUTH[@]}" --wait
    xcrun stapler staple "$APP"
    rm build/HeyDay.zip && ditto -c -k --keepParent "$APP" build/HeyDay.zip
    spctl -a -t exec -vv "$APP"
    echo "notarized build/HeyDay.zip"
    if [[ -n "${PUBLISH:-}" ]]; then
      git tag "v$VERSION" && git push origin "v$VERSION"
      gh release create "v$VERSION" build/HeyDay.zip --title "HeyDay v$VERSION" --generate-notes
    fi
    ;;
esac
