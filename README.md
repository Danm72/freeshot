# FreeShot

FreeShot is a free, native macOS menubar app that replaces CleanShot X. It uses AppKit, ScreenCaptureKit, Vision and Carbon hotkeys. It has no third-party dependencies.

## Build

```bash
swift build
swift test
scripts/make-app.sh            # builds and signs dist/FreeShot.app
scripts/make-app.sh --install  # also copies it to /Applications
```

The script signs with "Apple Development: Created via API (2SA7G962C4)". A stable signature keeps the Screen Recording grant across rebuilds. Set `FREESHOT_SIGN_IDENTITY` to use a different identity.

## Install

1. Quit CleanShot X. It holds the same hotkeys.
2. Run `scripts/make-app.sh --install`.
3. Open `/Applications/FreeShot.app`. The icon shows in the menubar.

## Hotkeys

| Hotkey | Action |
|---|---|
| ⇧⌘3 | Capture Fullscreen (the display under the cursor) |
| ⇧⌘4 | Capture Area |
| ⇧⌘5 | All-in-One |

On first launch FreeShot reads the hotkeys from the CleanShot X preferences (`pl.maketheweb.cleanshotx`). If they are not there, it uses the table above. You can change the hotkeys in Settings. If another app holds a hotkey, the menu shows a warning line for it.

## Other triggers

- URL scheme: `open freeshot://capture/fullscreen` (also `area`, `window`, `allinone`, `previous`, `ocr`, `record`).
- Headless capture: `FreeShot.app/Contents/MacOS/FreeShot --capture fullscreen --out /tmp/shot.png`. It writes the PNG, prints the path and exits.

## Permissions

FreeShot needs Screen Recording permission. On first launch it asks for it. Turn it on in System Settings > Privacy & Security > Screen & System Audio Recording, then reopen FreeShot. The hotkeys need no Accessibility permission.

## Defaults

Captures go to `~/screenshots` as `Screenshot 2026-10-02 at 10.21.18@2x.png`. After a capture FreeShot saves the file, copies the image and shows the Quick Access Overlay at the bottom left.

## Layout

| Directory | Contents |
|---|---|
| `Sources/FreeShotCore` | Pure logic with unit tests: settings, hotkeys, file names, coordinates, history, PNG export |
| `Sources/FreeShot/App` | App shell: menubar, hotkeys, URL scheme, CLI, `ActionRouter`, module protocols |
| `Sources/FreeShot/Capture` | Area overlay, window picker, All-in-One HUD |
| `Sources/FreeShot/QuickAccess` | After-capture pipeline and Quick Access Overlay |
| `Sources/FreeShot/Annotate` | Annotate editor |
| `Sources/FreeShot/Extras` | Pin, OCR, screen recording, Settings window |
