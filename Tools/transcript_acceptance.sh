#!/usr/bin/env bash
# CI: the vendored, pinned SMPC verifier must accept the Swift-produced transcript and reject a
# tampered copy (verify_round.py --transcript, cravage-transcript-2 mode).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FILE="${1:?usage: transcript_acceptance.sh <transcript.json>}"
if [ ! -f "$FILE" ]; then
  echo "No Swift-produced transcript at $FILE - TranscriptTests did not write it" >&2
  exit 1
fi
python3 "$HERE/verify_round.py" --transcript "$FILE"
TAMPERED="$(mktemp)"
trap 'rm -f "$TAMPERED"' EXIT
python3 -c 'import json, sys
t = json.load(open(sys.argv[1]))
t["average"] = "999"
json.dump(t, open(sys.argv[2], "w"))' "$FILE" "$TAMPERED"
if python3 "$HERE/verify_round.py" --transcript "$TAMPERED" > /dev/null; then
  echo "The pinned verifier accepted a tampered transcript" >&2
  exit 1
fi
echo "Tampered transcript rejected, as it must be"
