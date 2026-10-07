#!/usr/bin/env bash
# Archive the last commit (HEAD) from a clean copy, check the archive, and upload it to App Store
# Connect for TestFlight. Written after the first upload (2026-10-06), done by hand.
#
# Before running: raise CFBundleVersion in project.yml (App Store Connect refuses a build number it
# has seen), run xcodegen, commit and push. Xcode must be signed in to an Apple Account with App
# Store Connect access (Xcode > Settings > Accounts); "Failed to Use Accounts" means sign in again.
#
# Usage: Tools/upload_testflight.sh [--check-only]
#   --check-only builds and checks the archive without uploading.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
WORK="$ROOT/build/testflight"
CLEAN=""
cleanup() {
  if [ -n "$CLEAN" ]; then
    git -C "$ROOT" worktree remove --force "$CLEAN" || echo "Could not remove the clean copy at $CLEAN" >&2
  fi
}
trap cleanup EXIT

if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]; then
  echo "Note: the working folder has uncommitted changes; they are not in this build" >&2
fi
if [ "$(git -C "$ROOT" rev-parse HEAD)" != "$(git -C "$ROOT" rev-parse '@{u}' 2>/dev/null || true)" ]; then
  echo "HEAD is not pushed; push first so the uploaded build matches the repository" >&2
  exit 1
fi
TEAM="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' "$ROOT/Config/Local.xcconfig" 2>/dev/null | tr -d ' ')"
if [ -z "$TEAM" ]; then
  echo "No DEVELOPMENT_TEAM in Config/Local.xcconfig (see Config/Local.xcconfig.example)" >&2
  exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK"
CLEAN="$(cd "$(mktemp -d)" && pwd -P)/cravage"
git -C "$ROOT" worktree add --quiet --detach "$CLEAN" HEAD
cp "$ROOT/Config/Local.xcconfig" "$CLEAN/Config/"
echo "Archiving commit $(git -C "$ROOT" rev-parse --short HEAD)..."
xcodebuild archive -project "$CLEAN/Cravage.xcodeproj" -scheme Cravage -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$WORK/Cravage.xcarchive" \
  -allowProvisioningUpdates > "$WORK/archive.log" 2>&1 || {
    echo "Archive failed; see $WORK/archive.log" >&2
    tail -20 "$WORK/archive.log" >&2
    exit 1
  }

APP="$WORK/Cravage.xcarchive/Products/Applications/Cravage.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Info.plist")"
echo "Archived Cravage $VERSION ($BUILD)"
"$HERE/check_privacy_manifest.sh" "$APP"
DEBUG_APP="$(ls -d "$ROOT"/build/*/Build/Products/Debug-iphone*/Cravage.app 2>/dev/null | head -1 || true)"
if [ -n "$DEBUG_APP" ]; then
  "$HERE/check_stage_compiled_out.sh" "$APP" "$DEBUG_APP"
else
  echo "No local Debug build to compare against; skipping the stage check (CI runs it)" >&2
fi

if [ "${1:-}" = "--check-only" ]; then
  echo "Checked; not uploaded (--check-only)"
  exit 0
fi

cat > "$WORK/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>upload</string>
	<key>signingStyle</key><string>automatic</string>
	<key>teamID</key><string>$TEAM</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF
echo "Uploading $VERSION ($BUILD) to App Store Connect..."
if xcodebuild -exportArchive -archivePath "$WORK/Cravage.xcarchive" \
     -exportOptionsPlist "$WORK/ExportOptions.plist" -exportPath "$WORK/export" \
     -allowProvisioningUpdates > "$WORK/upload.log" 2>&1; then
  echo "Uploaded $VERSION ($BUILD). Apple emails when processing finishes (usually 5 to 30 minutes)."
else
  echo "Upload failed; see $WORK/upload.log" >&2
  grep -E "error|App Store Connect access" "$WORK/upload.log" >&2 || tail -10 "$WORK/upload.log" >&2
  exit 1
fi
