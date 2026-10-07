#!/usr/bin/env bash
# Installs pre-commit and commit-msg hooks that run the public-safety lint, so a watched marker is
# caught in a file or a commit message before it is committed rather than after CI sees it. Hooks are not tracked by git, so every clone
# runs this once. Skip a single commit with `git commit --no-verify` if you must.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
HOOK="$ROOT/.git/hooks/pre-commit"
cat > "$HOOK" <<'HOOK_BODY'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
if [ -x "$ROOT/Tools/check_public_safe.sh" ]; then
  "$ROOT/Tools/check_public_safe.sh" >/dev/null || {
    echo "pre-commit: public-safety lint failed. Run Tools/check_public_safe.sh to see what." >&2
    exit 1
  }
fi
HOOK_BODY
chmod +x "$HOOK"
echo "Installed $HOOK"
MSG_HOOK="$ROOT/.git/hooks/commit-msg"
cat > "$MSG_HOOK" <<'HOOK_BODY'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
if [ -x "$ROOT/Tools/check_public_safe.sh" ]; then
  "$ROOT/Tools/check_public_safe.sh" --message "$1"
fi
HOOK_BODY
chmod +x "$MSG_HOOK"
echo "Installed $MSG_HOOK"
