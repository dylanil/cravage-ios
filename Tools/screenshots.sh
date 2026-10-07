#!/usr/bin/env bash
# Capture the App Store screenshots from the real app on a simulator (PLAN: scripted screenshots,
# never drawn). Each scene is the Debug app launched with -cravageStage <scene>, which plays a real
# round against hidden in-app phones up to that screen (Cravage/ScreenshotStage.swift). Release builds do not
# contain the stage.
#
# Usage: Tools/screenshots.sh [simulator name] [output folder]
#   Defaults: "iPhone 17 Pro Max" (the 6.9-inch size, 1320x2868) and build/screenshots.
# Captures every scene in light and dark into <output>/<appearance>/<NN>-<scene>.png, then copies
# the listing set (five screens, light) to <output>/listing/<N>-<scene>.png.
# Room codes come from fresh keys, so they differ between runs; the rest is fixed.
# Each capture is kept once two frames in a row are identical; a screen that never settles is
# reported and the script exits non-zero.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
BUNDLE_ID="com.dylanliew.cravage"
SIM_NAME="${1:-iPhone 17 Pro Max}"
OUT="${2:-$ROOT/build/screenshots}"
SCENES="home newRoom lobby confirmCode enterFigure waiting result"
LISTING="home lobby confirmCode enterFigure result"
NICKNAME="Alice"
DERIVED="$ROOT/build/screenshots-derived"
LOG="$ROOT/build/screenshots-build.log"
mkdir -p "$OUT" "$(dirname "$LOG")"

# The newest iOS runtime that has a simulator of that name: an older one cannot run an iOS 26 app.
SIM="$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
name = sys.argv[1]
found = []
for runtime, devices in json.load(sys.stdin)["devices"].items():
    match = re.search(r"\.iOS-([0-9-]+)$", runtime)
    if not match:
        continue
    version = tuple(int(part) for part in match.group(1).split("-"))
    found += [(version, device["udid"]) for device in devices if device["name"] == name]
if found:
    print(max(found)[1])
' "$SIM_NAME")"
if [ -z "$SIM" ]; then
  echo "No available simulator named '$SIM_NAME'" >&2
  exit 1
fi
echo "Simulator: $SIM_NAME ($SIM)"

# Builds the working folder, so a layout can be checked before committing. Images for the store
# should come from a clean commit: more than one session edits this checkout.
if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]; then
  echo "Note: the working folder has uncommitted changes, and these captures include them" >&2
fi
echo "Building Debug for the simulator..."
xcodebuild -project "$ROOT/Cravage.xcodeproj" -scheme Cravage -configuration Debug \
  -destination "id=$SIM" -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build > "$LOG" 2>&1 || {
    echo "Build failed; see $LOG" >&2
    tail -20 "$LOG" >&2
    exit 1
  }
APP="$DERIVED/Build/Products/Debug-iphonesimulator/Cravage.app"

# Leave the simulator as it was found, even when a step below fails.
restore() {
  xcrun simctl terminate "$SIM" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl status_bar "$SIM" clear 2>/dev/null || true
  xcrun simctl ui "$SIM" appearance light 2>/dev/null || true
}
trap restore EXIT

xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" > /dev/null
xcrun simctl status_bar "$SIM" override --time 9:41 --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --operatorName "" \
  --batteryState discharging --batteryLevel 100
xcrun simctl install "$SIM" "$APP"

FRAME="$(mktemp -d)"
UNSETTLED=""
# Captures until two frames 0.6 s apart are identical, up to about ten seconds.
capture() {
  local file="$1" tries=0
  sleep 1.5
  xcrun simctl io "$SIM" screenshot "$FRAME/a.png" > /dev/null 2>&1
  while [ "$tries" -lt 15 ]; do
    sleep 0.6
    xcrun simctl io "$SIM" screenshot "$FRAME/b.png" > /dev/null 2>&1
    if cmp -s "$FRAME/a.png" "$FRAME/b.png"; then
      mv "$FRAME/b.png" "$file"
      return 0
    fi
    mv "$FRAME/b.png" "$FRAME/a.png"
    tries=$((tries + 1))
  done
  mv "$FRAME/a.png" "$file"
  return 1
}

for appearance in light dark; do
  xcrun simctl ui "$SIM" appearance "$appearance"
  mkdir -p "$OUT/$appearance"
  number=1
  for scene in $SCENES; do
    xcrun simctl terminate "$SIM" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl launch "$SIM" "$BUNDLE_ID" -cravageStage "$scene" -nickname "$NICKNAME" \
      -appearance system > /dev/null
    file="$OUT/$appearance/$(printf '%02d' "$number")-$scene.png"
    if capture "$file"; then state="settled"; else state="NOT SETTLED"; UNSETTLED="$UNSETTLED $file"; fi
    echo "$file $(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixel/ {printf "%s ", $2}')$state"
    number=$((number + 1))
  done
done

rm -rf "$FRAME"
rm -rf "$OUT/listing"
mkdir -p "$OUT/listing"
number=1
for scene in $LISTING; do
  cp "$OUT"/light/??-"$scene".png "$OUT/listing/$number-$scene.png"
  number=$((number + 1))
done
if [ -n "$UNSETTLED" ]; then
  echo "Still changing after ten seconds, check by eye:$UNSETTLED" >&2
  exit 1
fi
echo "Done: $OUT"
