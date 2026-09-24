#!/usr/bin/env bash
# CI: no user-visible string in the app may make a claim CLAUDE.md's "Honesty copy" section
# forbids - claims against collusion, about input honesty, about identity beyond the host's eyes,
# or that nothing is stored or sent. The fresh review of 2026-09-19 found two on the Home screen,
# carried over from an approved mockup; this stops the class coming back.
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
)

FOUND=0
for pattern in "${PATTERNS[@]}"; do
  # Only user-visible strings: a line whose first non-space characters are // is a code comment,
  # where the same words describe behaviour rather than claiming it to a user.
  # Info.plist and project.yml carry the permission prompt text iOS shows the user.
  if { grep -rni --include='*.swift' "$pattern" "$ROOT/Cravage"
       grep -ni "$pattern" "$ROOT/Cravage/Resources/Info.plist" "$ROOT/project.yml"; } \
       | grep -v ':[[:space:]]*//' > /tmp/honesty_hits 2>/dev/null; then
    echo "Forbidden claim '$pattern':" >&2
    cat /tmp/honesty_hits >&2
    FOUND=1
  fi
done

if [ "$FOUND" -ne 0 ]; then
  echo "" >&2
  echo "See CLAUDE.md, 'Honesty copy'. Allowed wording is listed there; changing the approved" >&2
  echo "Limitations text needs the owner." >&2
  exit 1
fi
echo "No forbidden honesty claims in the app's copy"
