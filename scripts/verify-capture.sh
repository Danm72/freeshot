#!/bin/bash
# Checks FreeShot's own Screen Recording grant with a headless fullscreen capture.
# It launches through LaunchServices (open), so TCC checks FreeShot.app and not the terminal.
# Usage: scripts/verify-capture.sh [/path/to/FreeShot.app]
set -euo pipefail

APP="${1:-/Applications/FreeShot.app}"
OUT="$(mktemp -d)/freeshot-verify.png"

if [[ ! -d "$APP" ]]; then
  echo "FAIL: $APP does not exist" >&2
  exit 1
fi

# open -W waits for the app to exit. Its exit status is not the app's status, so check the file.
open -n -W -a "$APP" --args --capture fullscreen --out "$OUT" || true

if [[ ! -s "$OUT" ]]; then
  echo "FAIL: no PNG at $OUT. Grant Screen Recording to FreeShot, then run this again." >&2
  exit 1
fi

if ! WIDTH=$(sips -g pixelWidth "$OUT" 2>/dev/null | awk '/pixelWidth/ {print $2}') || [[ -z "$WIDTH" ]]; then
  echo "FAIL: $OUT is not a readable image" >&2
  exit 1
fi

echo "OK: $OUT ($WIDTH px wide)"
