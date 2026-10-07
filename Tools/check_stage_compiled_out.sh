#!/usr/bin/env bash
# CI: the screenshot stage (Cravage/ScreenshotStage.swift) is in the Debug app and nowhere in the
# Release app. PLAN: Release cannot activate test-only transports or seeded states.
#
# Searches every file in each bundle, not just the main executable: Xcode puts Debug code in
# Cravage.debug.dylib, so a check of the executable alone found nothing in either build. The Debug
# bundle must match, which shows the search can fire at all (review, 2026-10-05).
#
# Usage: Tools/check_stage_compiled_out.sh <Release Cravage.app> <Debug Cravage.app>
set -euo pipefail
RELEASE="${1:?Release Cravage.app}"
DEBUG="${2:?Debug Cravage.app}"
PATTERN='cravageStage|ScreenshotStage'

for app in "$RELEASE" "$DEBUG"; do
  if [ ! -d "$app" ]; then
    echo "No app bundle at $app" >&2
    exit 1
  fi
done

if ! grep -r -a -l -E "$PATTERN" "$DEBUG" > /dev/null; then
  echo "The Debug app does not contain the stage, so this search proves nothing" >&2
  exit 1
fi
if grep -r -a -l -E "$PATTERN" "$RELEASE"; then
  echo "The Release app contains the screenshot stage (files above)" >&2
  exit 1
fi
echo "Screenshot stage: present in Debug, absent from Release"
