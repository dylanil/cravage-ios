#!/usr/bin/env bash
# Archive the last commit (HEAD) from a clean copy, check the archive, and upload it to App Store
# Connect for TestFlight. Written after the first upload (2026-10-06), done by hand.
#
# Before running: raise CFBundleVersion in project.yml (App Store Connect refuses a build number it
# has seen), run xcodegen, commit and push.
#
# Sign-in: an App Store Connect API key, when Tools/app_store_key.sh (a local helper outside this
# repository) has one in the Mac keychain, since a key does not expire until revoked; otherwise the
# Apple Account in Xcode > Settings > Accounts, whose sign-in does expire ("Failed to Use
# Accounts"). xcodebuild's -help text says the key serves -allowProvisioningUpdates; Apple's WWDC21
# session "Distribute apps in Xcode with cloud signing" passes it to -exportArchive and says
# xcodebuild needs credentials "to successfully cloud sign and upload". Apple names no minimum role
# for the key; Admin is the role forum reports agree on.
#
# Usage: Tools/upload_testflight.sh [--check-only]
#   --check-only builds and checks the archive without uploading.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
WORK="$ROOT/build/testflight"
CLEAN=""
KEYDIR=""
cleanup() {
  if [ -n "$CLEAN" ]; then
    git -C "$ROOT" worktree remove --force "$CLEAN" || echo "Could not remove the clean copy at $CLEAN" >&2
  fi
  if [ -n "$KEYDIR" ]; then
    rm -rf "$KEYDIR"
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

# The key is written for this run only, readable by this account only, and removed on exit.
AUTH=()
KEY_ID=""
if [ -x "$HERE/app_store_key.sh" ]; then
  KEYDIR="$(mktemp -d)"
  read -r KEY_ID ISSUER < <("$HERE/app_store_key.sh" write "$KEYDIR") || true
fi
if [ -n "$KEY_ID" ]; then
  AUTH=(-authenticationKeyPath "$KEYDIR/AuthKey_$KEY_ID.p8" -authenticationKeyID "$KEY_ID"
        -authenticationKeyIssuerID "$ISSUER")
  echo "Signing in with App Store Connect key $KEY_ID"
else
  echo "Signing in with the Apple Account in Xcode (no App Store Connect key stored)"
fi

rm -rf "$WORK"
mkdir -p "$WORK"
CLEAN="$(cd "$(mktemp -d)" && pwd -P)/cravage"
git -C "$ROOT" worktree add --quiet --detach "$CLEAN" HEAD
cp "$ROOT/Config/Local.xcconfig" "$CLEAN/Config/"
echo "Archiving commit $(git -C "$ROOT" rev-parse --short HEAD)..."
xcodebuild archive -project "$CLEAN/Cravage.xcodeproj" -scheme Cravage -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$WORK/Cravage.xcarchive" \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} > "$WORK/archive.log" 2>&1 || {
    echo "Archive failed; see $WORK/archive.log" >&2
    tail -20 "$WORK/archive.log" >&2
    exit 1
  }

APP="$WORK/Cravage.xcarchive/Products/Applications/Cravage.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Info.plist")"
echo "Archived Cravage $VERSION ($BUILD)"
# The export compliance answer (docs/APP_STORE.md) travels in the build, so App Store Connect does
# not ask for it; an archive without it would wait in App Store Connect for the questionnaire.
if [ "$(/usr/libexec/PlistBuddy -c 'Print ITSAppUsesNonExemptEncryption' "$APP/Info.plist" 2>/dev/null)" != "false" ]; then
  echo "The archive does not declare ITSAppUsesNonExemptEncryption = NO (see docs/APP_STORE.md)" >&2
  exit 1
fi
"$HERE/check_privacy_manifest.sh" "$APP"
# The stage check needs a Debug build of the same commit to show its search can fire; build one
# rather than skip the check or compare against whatever older build is lying around.
echo "Building a Debug copy of the same commit for the stage check..."
xcodebuild build -project "$CLEAN/Cravage.xcodeproj" -scheme Cravage -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath "$WORK/debug" CODE_SIGNING_ALLOWED=NO \
  > "$WORK/debug.log" 2>&1 || {
    echo "Debug build failed; see $WORK/debug.log" >&2
    tail -20 "$WORK/debug.log" >&2
    exit 1
  }
"$HERE/check_stage_compiled_out.sh" "$APP" "$WORK/debug/Build/Products/Debug-iphoneos/Cravage.app"

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
     -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} > "$WORK/upload.log" 2>&1; then
  echo "Uploaded $VERSION ($BUILD). Apple emails when processing finishes (usually 5 to 30 minutes)."
else
  echo "Upload failed; see $WORK/upload.log" >&2
  grep -E "error|App Store Connect access" "$WORK/upload.log" >&2 || tail -10 "$WORK/upload.log" >&2
  if grep -q "Failed to Use Accounts" "$WORK/upload.log"; then
    echo "Xcode's sign-in has expired: sign in again in Xcode > Settings > Accounts, or store an" >&2
    echo "App Store Connect key so uploads stop depending on it." >&2
  fi
  exit 1
fi
