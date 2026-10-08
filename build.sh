#!/bin/bash
# ./build.sh            build HeyDay.app
# ./build.sh install    build, copy to ~/Applications, launch at login
set -euo pipefail
cd "$(dirname "$0")"

APP=build/HeyDay.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -enable-bare-slash-regex -target "$(uname -m)-apple-macos13" \
  Sources/HeyDay.swift -o "$APP/Contents/MacOS/HeyDay" 2>&1 | grep -v "^$" || true
test -x "$APP/Contents/MacOS/HeyDay"

cat >"$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.rock.heyday</string>
  <key>CFBundleName</key><string>HeyDay</string>
  <key>CFBundleExecutable</key><string>HeyDay</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign -s - --force "$APP" >/dev/null
echo "built $APP"

if [[ "${1:-}" == "install" ]]; then
  mkdir -p ~/Applications
  pkill -x HeyDay || true
  rm -rf ~/Applications/HeyDay.app && cp -R "$APP" ~/Applications/
  osascript -e 'tell application "System Events" to delete (every login item whose name is "HeyDay")' >/dev/null 2>&1 || true
  osascript -e 'tell application "System Events" to make login item at end with properties {path:"'"$HOME"'/Applications/HeyDay.app", hidden:false}' >/dev/null 2>&1 || true
  open ~/Applications/HeyDay.app
  echo "installed + added to login items"
fi
