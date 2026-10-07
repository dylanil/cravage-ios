#!/usr/bin/env bash
# CI: no user-visible string in the app may make a claim CONTRIBUTING.md's "Honesty copy" section
# forbids - claims against collusion, about input honesty, about identity beyond the host's eyes,
# or that nothing is stored or sent. A design that is approved still has its claims checked here.
#
# It greps source text, so it is deliberately blunt: a phrase that is genuinely fine but matches
# should be reworded, or the pattern narrowed with a comment saying why.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"

PATTERNS=(
  'no data leaves'
  'nothing stored'
  'nothing is sent'
  'nothing leaves'
  'nobody sees'
  'no one sees'
  'nobody can see'
  'everyone trusts'
  'completely private'
  'totally private'
  'fully anonymous'
  'totally anonymous'
  'safe to share'
  'cannot be traced'
  'impossible to work out'
  'sends nothing'
  'nothing saved'
  'saves nothing'
)

# The listing copy only: the rest of APP_STORE.md is working notes (the privacy label's rationale
# rightly says what is not sent to the developer).
LISTING="$(mktemp)"
trap 'rm -f "$LISTING"' EXIT
awk '/^## Listing copy/ {on = 1; next} /^## / {on = 0} on' "$ROOT/docs/APP_STORE.md" > "$LISTING"

FOUND=0
for pattern in "${PATTERNS[@]}"; do
  # Only user-visible strings: a line whose first non-space characters are // is a code comment,
  # where the same words describe behaviour rather than claiming it to a user.
  # Info.plist and project.yml carry the permission prompt text iOS shows the user, and
  # $LISTING the store listing copy, which said "nothing saved" after the app began saving the
  # appearance choice (2026-10-06).
  if { grep -rni --include='*.swift' "$pattern" "$ROOT/Cravage"
       grep -ni "$pattern" "$ROOT/Cravage/Resources/Info.plist" "$ROOT/project.yml" "$LISTING"; } \
       | grep -v ':[[:space:]]*//' > /tmp/honesty_hits 2>/dev/null; then
    echo "Forbidden claim '$pattern':" >&2
    cat /tmp/honesty_hits >&2
    FOUND=1
  fi
done

if [ "$FOUND" -ne 0 ]; then
  echo "" >&2
  echo "See CONTRIBUTING.md, 'Honesty copy'. Allowed wording is listed there; changing the approved" >&2
  echo "Limitations text needs sign-off." >&2
  exit 1
fi
echo "No forbidden honesty claims in the app's copy"
