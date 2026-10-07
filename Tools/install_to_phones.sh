#!/usr/bin/env bash
# Build Cravage for a device and install it on every paired iPhone this Mac can reach.
#
# Discovers phones rather than hard-coding them, so no device identifier is tracked.
#
# The usual failure is a locked phone: devicectl reports that the developer disk image could not be
# mounted and the device is locked. Unlock every phone and set Auto-Lock to Never before running.
#
# Builds the last commit (HEAD) from a clean copy, not the working folder, so unfinished edits
# never reach the phones. Pass --working-tree to build the folder as it stands.
#
# Usage: Tools/install_to_phones.sh [--working-tree]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
BUNDLE_ID="com.dylanliew.cravage"
DERIVED="$ROOT/build/phones-derived"
LOG="$ROOT/build/phones-build.log"
mkdir -p "$ROOT/build"

SOURCE="$ROOT"
CLEAN=""
LIST=""
# One exit handler for everything: a second `trap ... EXIT` would replace this one.
cleanup() {
  if [ -n "$LIST" ]; then rm -f "$LIST"; fi
  if [ -n "$CLEAN" ]; then
    git -C "$ROOT" worktree remove --force "$CLEAN" || echo "Could not remove the clean copy at $CLEAN" >&2
  fi
}
trap cleanup EXIT
if [ "${1:-}" = "--working-tree" ]; then
  echo "Building the working folder as it stands"
else
  CLEAN="$(mktemp -d)/cravage"
  git -C "$ROOT" worktree add --quiet --detach "$CLEAN" HEAD
  # Signing reads the git-ignored team ID file, which a fresh copy does not have.
  if [ -f "$ROOT/Config/Local.xcconfig" ]; then cp "$ROOT/Config/Local.xcconfig" "$CLEAN/Config/"; fi
  SOURCE="$CLEAN"
  echo "Building commit $(git -C "$ROOT" rev-parse --short HEAD) from a clean copy"
  if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]; then
    echo "(the working folder has uncommitted changes; they are not in this build)"
  fi
fi

xcodebuild -project "$SOURCE/Cravage.xcodeproj" -scheme Cravage \
  -destination 'generic/platform=iOS' -configuration Debug \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates build > "$LOG" 2>&1 || {
    echo "Build failed; see $LOG" >&2
    tail -20 "$LOG" >&2
    exit 1
  }

APP="$DERIVED/Build/Products/Debug-iphoneos/Cravage.app"
if [ ! -d "$APP" ]; then
  echo "No built Cravage.app found" >&2
  exit 1
fi
echo "Built: $APP"

LIST="$(mktemp)"
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
  # Capture the whole output first: `grep -q` stops reading at the first match, and under pipefail
  # the installer's resulting broken pipe turned every successful install into a reported failure.
  result="$(xcrun devicectl device install app --device "$udid" "$APP" < /dev/null 2>&1 || true)"
  if grep -q 'App installed' <<< "$result"; then
    xcrun devicectl device process launch --device "$udid" "$BUNDLE_ID" < /dev/null > /dev/null 2>&1 \
      && echo "installed and launched" || echo "installed (tap the app to open it)"
  else
    echo "FAILED - unlock it and check it is on this Wi-Fi"
    FAILED=1
  fi
done <<< "$PHONES"

exit "$FAILED"
