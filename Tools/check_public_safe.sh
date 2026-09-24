#!/usr/bin/env bash
# Public-safety lint: tracked documents describe the product, never the people behind it, and no
# account identifiers reach the tree. Scans what is actually committed or staged (the index), so it
# catches a staged change before it lands. Owner-personal notes belong in .git/agents/private/.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
fail=0
# 1. Prose markers for owner-personal material.
PATTERN='SETUP_MAC|Remote Desktop|Screen Sharing|MacBook|Windows laptop|dylan\.liew@|password|partner|wife|husband|beginner|unfamiliar|layperson|coding experience|never billed|borrow'
# Excluded: the imported third-party review documents (verbatim by design) and this script itself.
EXCLUDE='docs/review/2026-09-12-(plan-review|coding-guardrails)\.md|Tools/check_public_safe\.sh'
if git ls-files -z -- '*.md' '*.swift' '*.yml' '*.sh' '*.py' \
   | grep -z -v -E "$EXCLUDE" \
   | xargs -0 git grep --cached -n -i -E "$PATTERN" -- ; then
  echo "Owner-personal marker found in a tracked or staged file. Move it to .git/agents/private/ or memory." >&2
  fail=1
fi
# 1b. The same scan over files that are not in the index yet. Scanning only the index let a new
# file pass this check and then fail it in CI once staged (2026-09-24): the lint had been run
# before `git add`, so the file it was meant to judge was invisible to it.
NEW_FILES="$(git ls-files -o --exclude-standard -- '*.md' '*.swift' '*.yml' '*.sh' '*.py' \
             | grep -v -E "$EXCLUDE" || true)"
if [ -n "$NEW_FILES" ]; then
  if printf '%s\n' "$NEW_FILES" | tr '\n' '\0' | xargs -0 grep -n -i -E "$PATTERN" -- ; then
    echo "Owner-personal marker found in a new, not-yet-staged file. Fix it before adding it." >&2
    fail=1
  fi
fi
# 2. Apple team identifiers written by Xcode into project files (ten alphanumerics).
if git grep --cached -n -E 'DEVELOPMENT_TEAM *= *"?[A-Z0-9]{10}"?' -- '*.pbxproj' '*.xcconfig' '*.plist' '*.yml' ; then
  echo "Apple team ID found in a tracked or staged project file. Keep it in an ignored xcconfig." >&2
  fail=1
fi
if [ "$fail" -ne 0 ]; then exit 1; fi
echo "public-safe: no owner-personal markers or team IDs in tracked or staged files"
