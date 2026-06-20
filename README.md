# Ezshot

[繁體中文](README.zh_TW.md)

Ezshot is a small native macOS screenshot and image-markup utility. It runs in the menu bar, captures screenshots into a tabbed editor, and only writes files when you explicitly save with `Cmd+S`.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain
- Screen Recording permission for screenshot capture

## Features

- Native macOS app with a menu bar status item and custom camera icon.
- Regular macOS app presence, so editor windows can be focused through `Cmd+Tab`; the app switcher uses a soft pink rounded-square camera icon.
- Global capture shortcuts:
  - `Option+Shift+R`: select a screen region.
  - `Option+Shift+A`: capture the current focused window.
  - `Option+Shift+W`: pick a window to capture.
- Pick-window capture can select Ezshot's own editor windows.
- Region selection overlay with crosshair cursor, horizontal/vertical guide lines, and drag selection.
- Optional delayed capture with visible countdown after the capture target is selected.
- Tabbed screenshot editor. Each capture opens as a new tab/window and remains unsaved until `Cmd+S`.
- Drag image files into an empty or existing editor window to import them as new editable tabs.
- Editor tools:
  - Persistent crop handles with live crop preview.
  - Line, arrow, and mosaic tools.
  - Undo for edits.
  - Copy edited image to the clipboard.
  - Line color and width controls.
- Optional automatic clipboard copy after capture.
- Language setting for system language, Traditional Chinese, or English. Unsupported system languages fall back to English.
- Appearance setting for system theme, light mode, or dark mode.

## Saving

`Cmd+S` saves only the current tab. The first save shows a macOS save panel with a default PNG filename. Later saves overwrite the same file path.

## Development

```sh
swift build
swift run ezshot-core-tests
sh scripts/run-app.sh --rebuild
sh scripts/run-app.sh
```

The app runs as a menu bar utility. Use the status menu to start a capture, show the screenshot window, toggle automatic clipboard copy, or quit.

Use `scripts/run-app.sh` for manual testing instead of `swift run ezshot`. macOS Screen Recording permission is tied to the launched app identity. `scripts/run-app.sh --rebuild` rebuilds and signs `.build/Ezshot.app`; plain `scripts/run-app.sh` relaunches the existing bundle without changing its signature, which avoids disturbing Screen Recording permission during repeated manual tests. The local app bundle runs as a regular app so editor windows can be focused through `Cmd+Tab`.

## Project Layout

```text
src/EzshotApp/        AppKit menu bar app, capture overlays, editor UI
src/EzshotCore/       document and preference model code
tests/EzshotCoreTests/ lightweight executable test runner
scripts/run-app.sh    local build/sign/launch helper
```
