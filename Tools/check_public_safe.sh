#!/usr/bin/env bash
# Public-safety lint: tracked documents describe the product, never the people behind it.
# Fails if any tracked text file mentions personal-setup, account, family or experience-level
# markers. Owner-personal notes belong in the untracked .git/agents/private/ tree.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
PATTERN='SETUP_MAC|Remote Desktop|Screen Sharing|MacBook|Windows laptop|dylan.liew@|password|partner|wife|husband|beginner|unfamiliar|layperson|coding experience|never billed|borrow'
# Excluded: the imported third-party review documents (verbatim by design) and this script itself.
EXCLUDE='docs/review/2026-09-12-(plan-review|coding-guardrails)\.md|Tools/check_public_safe\.sh'
if git ls-files -z -- '*.md' '*.swift' '*.yml' '*.sh' '*.py' \
   | grep -z -v -E "$EXCLUDE" \
   | xargs -0 grep -n -i -E "$PATTERN" ; then
  echo "Owner-personal marker found in a tracked file. Move it to .git/agents/private/ or memory." >&2
  exit 1
fi
echo "public-safe: no owner-personal markers in tracked files"
