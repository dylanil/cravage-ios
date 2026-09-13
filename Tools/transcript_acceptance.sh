#!/usr/bin/env bash
# CI: the Python v2 check must accept the Swift-produced transcript and reject a tampered copy.
# Tools/check_transcript_v2.py is the interim twin of the approved verify_round.py v2 mode.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FILE="${1:?usage: transcript_acceptance.sh <transcript.json>}"
if [ ! -f "$FILE" ]; then
  echo "No Swift-produced transcript at $FILE - TranscriptTests did not write it" >&2
  exit 1
fi
python3 "$HERE/check_transcript_v2.py" "$FILE"
TAMPERED="$(mktemp)"
trap 'rm -f "$TAMPERED"' EXIT
python3 -c 'import json, sys
t = json.load(open(sys.argv[1]))
t["average"] = "999"
json.dump(t, open(sys.argv[2], "w"))' "$FILE" "$TAMPERED"
if python3 "$HERE/check_transcript_v2.py" "$TAMPERED" > /dev/null; then
  echo "The v2 check accepted a tampered transcript" >&2
  exit 1
fi
echo "Tampered transcript rejected, as it must be"
