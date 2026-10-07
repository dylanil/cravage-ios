#!/usr/bin/env bash
# CI: no screen the router can reach is a placeholder.
#
# On 2026-09-19 a host could not readmit anyone after a restart: the router correctly returned the
# restart-offer screen, but that screen was a stub reading "Not built yet" whose only button left
# the room. Every routing test passed, because the tests asserted which case the router returned,
# not whether the case led anywhere usable. A screen that is not built is not routed: leave the
# case unhandled and let the compiler's exhaustive switch be the reminder.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"

if grep -rniE 'Unbuilt|ComingSoon|PlaceholderView|Not built yet|screen is designed but not written' \
     --include='*.swift' "$ROOT/Cravage" > /tmp/placeholder_hits 2>/dev/null; then
  echo "A placeholder screen is reachable from the router:" >&2
  cat /tmp/placeholder_hits >&2
  echo "" >&2
  echo "Build the screen, or remove its case so the compiler refuses the switch." >&2
  exit 1
fi
echo "No placeholder screens are reachable"
