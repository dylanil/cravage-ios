#!/usr/bin/env bash
# Build Cravage for a device and install it on every paired iPhone this Mac can reach.
#
# Written after the 2026-09-19 device session, where the build-install-launch loop was run by hand
# six times. Discovers phones rather than hard-coding them, so no device identifier is tracked.
#
# The usual failure is a locked phone: devicectl reports that the developer disk image could not be
# mounted and the device is locked. Unlock every phone and set Auto-Lock to Never before running.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
BUNDLE_ID="com.dylanliew.cravage"

echo "Building for a device..."
xcodebuild -project "$ROOT/Cravage.xcodeproj" -scheme Cravage \
  -destination 'generic/platform=iOS' -configuration Debug \
  -allowProvisioningUpdates build > /tmp/cravage_device_build.log 2>&1 || {
    echo "Build failed; see /tmp/cravage_device_build.log" >&2
    tail -20 /tmp/cravage_device_build.log >&2
    exit 1
  }

APP="$(find "$HOME/Library/Developer/Xcode/DerivedData/Cravage-"*/Build/Products/Debug-iphoneos \
        -maxdepth 1 -name 'Cravage.app' 2>/dev/null | head -1)"
if [ -z "$APP" ]; then
  echo "No built Cravage.app found" >&2
  exit 1
fi
echo "Built: $APP"

LIST="$(mktemp)"
trap 'rm -f "$LIST"' EXIT
xcrun devicectl list devices --json-output "$LIST" > /dev/null 2>&1

PHONES="$(python3 -c '
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
for device in devices:
    hardware = device["hardwareProperties"]
    if hardware.get("deviceType") != "iPhone":
        continue
    # Simulators report deviceType "iPhone" too; only real, paired phones can take this build.
    if device.get("visibilityClass") == "simulators":
        continue
    print(hardware["udid"], device["deviceProperties"].get("name", "iPhone"), sep="\t")
' "$LIST")"

if [ -z "$PHONES" ]; then
  echo "No paired iPhones found" >&2
  exit 1
fi

FAILED=0
while IFS=$'\t' read -r udid name; do
  printf '%s: ' "$name"
  if xcrun devicectl device install app --device "$udid" "$APP" 2>&1 | grep -q 'App installed'; then
    xcrun devicectl device process launch --device "$udid" "$BUNDLE_ID" > /dev/null 2>&1 \
      && echo "installed and launched" || echo "installed (tap the app to open it)"
  else
    echo "FAILED - unlock it and check it is on this Wi-Fi"
    FAILED=1
  fi
done <<< "$PHONES"

exit "$FAILED"
