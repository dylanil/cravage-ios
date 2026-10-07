#!/usr/bin/env bash
# Public-safety lint: tracked files describe the product, and no account identifiers reach the tree.
#
# The patterns themselves are not written here, since spelling them would put them in the tree the
# check keeps clean. They are read, one extended regex per line, from the ignored
# Tools/.private-patterns, or in CI from the PUBLIC_SAFE_PATTERNS secret.
#
# Usage: Tools/check_public_safe.sh             scan the index, the working tree and new files
#        Tools/check_public_safe.sh --message F scan a commit message file (the commit-msg hook)
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
fail=0

PATTERN_SOURCE=""
if [ -n "${PUBLIC_SAFE_PATTERNS:-}" ]; then
  PATTERN_SOURCE="$PUBLIC_SAFE_PATTERNS"
elif [ -f "$ROOT/Tools/.private-patterns" ]; then
  PATTERN_SOURCE="$(cat "$ROOT/Tools/.private-patterns")"
fi
PATTERN="$(printf '%s\n' "$PATTERN_SOURCE" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$' | paste -sd '|' - || true)"
if [ -z "$PATTERN" ]; then
  if [ -n "${CI:-}" ]; then
    echo "public-safe: no patterns (set the PUBLIC_SAFE_PATTERNS secret)" >&2
    exit 1
  fi
  echo "public-safe: warning: no Tools/.private-patterns on this machine; scanning team IDs only" >&2
fi

if [ "${1:-}" = "--message" ]; then
  if [ -n "$PATTERN" ] && grep -v '^#' "$2" | grep -n -i -E "$PATTERN"; then
    echo "Commit message carries a watched marker. Describe the change, not how it came about." >&2
    exit 1
  fi
  exit 0
fi

GLOBS=('*.md' '*.swift' '*.yml' '*.yaml' '*.sh' '*.py' '*.json' '*.txt' '*.xcconfig' '*.plist' '*.storekit' 'LICENSE')
# The imported third-party plan review is kept verbatim; this script names the paths it guards.
EXCLUDE='docs/review/2026-09-12-plan-review\.md|Tools/check_public_safe\.sh'

if [ -n "$PATTERN" ]; then
  # 1. What is committed or staged (the index).
  if git ls-files -z -- "${GLOBS[@]}" | grep -z -v -E "$EXCLUDE" \
     | xargs -0 git grep --cached -n -i -E "$PATTERN" -- ; then
    echo "Watched marker in a tracked or staged file." >&2
    fail=1
  fi
  # 2. The working tree's copy of tracked files, so unstaged edits are judged too.
  if git ls-files -z -- "${GLOBS[@]}" | grep -z -v -E "$EXCLUDE" \
     | xargs -0 grep -n -i -E "$PATTERN" -- ; then
    echo "Watched marker in the working tree." >&2
    fail=1
  fi
  # 3. Files not yet in the index, so a new file is judged before it is added.
  NEW_FILES="$(git ls-files -o --exclude-standard -- "${GLOBS[@]}" | grep -v -E "$EXCLUDE" || true)"
  if [ -n "$NEW_FILES" ] && printf '%s\n' "$NEW_FILES" | tr '\n' '\0' | xargs -0 grep -n -i -E "$PATTERN" -- ; then
    echo "Watched marker in a new, not-yet-staged file." >&2
    fail=1
  fi
fi

# 4. Working notes have their own home and never enter this repository.
if git ls-files | grep -E '^(CLAUDE\.md|AGENTS\.md|\.claude/|\.agents/|docs/retros/)'; then
  echo "A working-notes file is tracked. Remove it from the index (git rm --cached)." >&2
  fail=1
fi

# 5. Apple team identifiers written by Xcode into project files (ten alphanumerics).
if git grep --cached -n -E 'DEVELOPMENT_TEAM *= *"?[A-Z0-9]{10}"?' -- '*.pbxproj' '*.xcconfig' '*.plist' '*.yml' ; then
  echo "Apple team ID found in a tracked or staged project file. Keep it in an ignored xcconfig." >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "public-safe: no watched markers, working notes or team IDs in tracked or staged files"
