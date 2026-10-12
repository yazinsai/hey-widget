<h1 align="center">HeyDay</h1>

<p align="center"><strong>Your HEY Calendar, always on your desktop.</strong><br>
See your whole day at a glance, and plan it by dragging, without opening a browser tab.</p>

<p align="center">
  <a href="https://github.com/yazinsai/hey-widget/releases/latest/download/HeyDay.zip"><img src="https://img.shields.io/badge/Download-HeyDay%20for%20macOS-111?style=for-the-badge&logo=apple" alt="Download HeyDay for macOS"></a>
</p>
<p align="center">
  <img src="https://img.shields.io/github/v/release/yazinsai/hey-widget?label=release" alt="Latest release">
  <img src="https://img.shields.io/badge/macOS-13%2B-blue" alt="macOS 13+">
  <img src="https://img.shields.io/badge/notarized-Apple-success" alt="Notarized by Apple">
  <img src="https://img.shields.io/github/license/yazinsai/hey-widget" alt="MIT license">
</p>

<p align="center"><img src="docs/demo.gif" width="400" alt="HeyDay demo: drag to create an event, resize one, switch days"></p>

## Why HeyDay

- **Know what's next without looking for it.** Your day sits on the desktop as a timeline, with a live "now" line and the current event highlighted.
- **Plan by hand, not by form.** Drag empty space to create an event. Drag an event to move it, pull its edge to resize, double-click to rename.
- **Instant, even when switching days.** Days are cached and neighbouring days prefetched, so flipping through your week feels local.
- **Set up in under a minute.** Download, open, click **Install**, sign in. No Terminal, no config files.
- **Stays out of the way.** It lives behind your windows like part of the wallpaper, or floats above them if you prefer. It opens at login and runs from the menu bar.

## Features

- Day timeline with live "now" line and current-event highlight
- Create events by dragging, or double-click for a quick one
- Move, resize, rename and delete events in place
- Repeating events: edits apply to that day only, never the whole series
- All-day events in a strip under the header
- Day navigation with a one-click jump back to **Today**
- Settings: target calendar, time zone, quick-event length, hour height, visible hours (e.g. 8a–5p), float above windows, open at login

## Install

You need macOS 13 or later and a HEY account. That's it.

[**Download HeyDay.zip**](https://github.com/yazinsai/hey-widget/releases/latest/download/HeyDay.zip), unzip, drag `HeyDay.app` into Applications and open it. It's signed and notarized by Apple, so it opens like any other app.

Or from Terminal:

```sh
curl -fsSL https://github.com/yazinsai/hey-widget/releases/latest/download/HeyDay.zip -o /tmp/HeyDay.zip && ditto -xk /tmp/HeyDay.zip /Applications && open /Applications/HeyDay.app
```

### First run

HeyDay walks you through the rest in the widget itself:

1. **Install the hey CLI**: one click. It runs HEY's [official installer](https://www.hey.com/agents/) into `~/.local/bin`. No admin password, nothing else to set up.
2. **Sign in to HEY**: your browser opens HEY's sign-in page. Approve it and the widget loads your day.

If you already have the `hey` CLI and are signed in, HeyDay skips straight to your calendar. It also adds itself to your login items; turn that off under Settings → Open at login.

HeyDay looks for `hey` in `$HEY_PATH`, `~/.local/bin`, `~/bin`, `~/go/bin`, `/opt/homebrew/bin`, then `/usr/local/bin`. Use the menu bar icon → **Sign Out of HEY** to switch accounts.

### Build from source

Needs Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/yazinsai/hey-widget.git
cd hey-widget
./build.sh install
```

This builds `HeyDay.app`, copies it to `~/Applications` and launches it. `./build.sh` alone builds into `build/`.

### Releasing

Needs a Developer ID Application certificate in your keychain and a notarytool profile (`xcrun notarytool store-credentials heyday-notary ...`). Then:

```sh
PUBLISH=1 VERSION=v0.2.0 ./build.sh release
```

That builds a universal (Apple silicon + Intel) app, signs it with hardened runtime, notarizes and staples it, then tags the version and creates the GitHub release with `build/HeyDay.zip`. Without `PUBLISH=1` it stops after the notarized zip.

## Usage

- Drag the header to move the widget; resize from the window edges.
- Hover the header for day navigation and the settings gear.
- The menu bar icon has Refresh, Settings and Quit.
- A red dot next to the date means the last `hey` call failed; hover it for the error, click to dismiss.

New events go to your **Personal** calendar by default; pick another in Settings.

### Demo mode

`HEYDAY_DEMO=1` shows sample events with the clock pinned to 11:20 (no `hey` calls). Add `HEYDAY_SNAPSHOT=out.png` to write a 2x PNG of the window and quit — that's how `docs/screenshot.png` is made:

```sh
HEYDAY_DEMO=1 HEYDAY_SNAPSHOT=$PWD/docs/screenshot.png ./build/HeyDay.app/Contents/MacOS/HeyDay
swift scripts/desktop-shot.swift docs/screenshot.png docs/screenshot-desktop.png
```

The second command places it on a generated desktop.

`scripts/demo-gif.sh` renders `docs/demo.gif`: with `HEYDAY_RECORD=dir` the app plays a scripted session (drag-create, type, resize, switch days) using synthetic input and writes each frame, then ffmpeg turns them into a GIF. Needs ffmpeg and ImageMagick.

## License

[MIT](LICENSE)
