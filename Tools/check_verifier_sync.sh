#!/usr/bin/env bash
# Tools/verify_round.py is vendored VERBATIM from the SMPC web repo so the phone's transcript is
# checked by exactly the same code as the web app's. It is pinned to a specific upstream commit and
# checksum: upstream changes are adopted deliberately (re-vendor, re-pin, review), never silently.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
EXPECTED_SHA256="879f990218b7174e4c884d6877b301bdd55d763e99a9e5cc380e7c2758b99736"
PINNED_COMMIT="06b70614b0d4fae763e931f0eab5cc47d231ce0b"
ACTUAL="$(shasum -a 256 "$HERE/verify_round.py" 2>/dev/null | cut -d' ' -f1 || sha256sum "$HERE/verify_round.py" | cut -d' ' -f1)"
if [ "$ACTUAL" = "$EXPECTED_SHA256" ]; then
  echo "verify_round.py matches the pinned copy (SMPC commit $PINNED_COMMIT)"
else
  echo "verify_round.py does not match the pinned checksum." >&2
  echo "  expected $EXPECTED_SHA256" >&2
  echo "  actual   $ACTUAL" >&2
  echo "Re-vendor from https://github.com/dylanil/SMPC/blob/<commit>/verify_round.py and update both pins." >&2
  exit 1
fi
