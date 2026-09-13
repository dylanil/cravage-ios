#!/usr/bin/env bash
# Public-safety lint: tracked documents describe the product, never the people behind it.
# Fails if any tracked text file mentions personal-setup, account, family or experience-level
# markers. Owner-personal notes belong in the untracked .git/agents/private/ tree.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
PATTERN='SETUP_MAC|Remote Desktop|Screen Sharing|MacBook|Windows laptop|Gmail|password|partner|wife|husband|beginner|unfamiliar|layperson|coding experience|never billed|borrow'
# Imported third-party review documents are verbatim by design; everything else is checked.
if git ls-files -z -- '*.md' '*.swift' '*.yml' '*.sh' '*.py' \
   | grep -z -v -E 'docs/review/2026-09-12-(plan-review|coding-guardrails)\.md' \
   | xargs -0 grep -n -i -E "$PATTERN" ; then
  echo "Owner-personal marker found in a tracked file. Move it to .git/agents/private/ or memory." >&2
  exit 1
fi
echo "public-safe: no owner-personal markers in tracked files"
