#!/usr/bin/env bash
# Builds dist/FreeShot.app (release), signs it, and with --install copies it to /Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    -h|--help) echo "usage: scripts/make-app.sh [--install]"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 64 ;;
  esac
done

# Signing identity: FREESHOT_SIGN_IDENTITY, else the first "Apple Development" identity
# in the keychain, else ad-hoc ("-"). Ad-hoc builds lose the Screen Recording grant on rebuild.
if [[ -n "${FREESHOT_SIGN_IDENTITY:-}" ]]; then
  IDENTITY="$FREESHOT_SIGN_IDENTITY"
else
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
  IDENTITY="${IDENTITY:--}"
fi
BUNDLE_ID="ie.mawla.freeshot"
VERSION="${FREESHOT_VERSION:-0.1.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
SCRATCH="${FREESHOT_SCRATCH:-.build}"

swift build -c release --scratch-path "$SCRATCH"
BIN_DIR="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)"

APP="$ROOT/dist/FreeShot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/FreeShot" "$APP/Contents/MacOS/FreeShot"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>FreeShot</string>
  <key>CFBundleDisplayName</key><string>FreeShot</string>
  <key>CFBundleExecutable</key><string>FreeShot</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSScreenCaptureUsageDescription</key><string>FreeShot captures your screen when you take a screenshot or a recording.</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>${BUNDLE_ID}</string>
      <key>CFBundleURLSchemes</key><array><string>freeshot</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP/Contents/PkgInfo"

plutil -lint "$APP/Contents/Info.plist"
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"

if [[ "$INSTALL" == 1 ]]; then
  if pgrep -x FreeShot >/dev/null; then
    echo "Quit the running FreeShot first." >&2
    exit 1
  fi
  rm -rf /Applications/FreeShot.app
  cp -R "$APP" /Applications/FreeShot.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/FreeShot.app
  echo "Installed /Applications/FreeShot.app"
fi
