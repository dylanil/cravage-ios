#!/usr/bin/env python3
"""Check a transcript exported by the Cravage iPhone app.

    python3 Tools/verify_transcript.py cravage-transcript.json

Runs the pinned web verifier's cravage-transcript-2 checks and nothing else. The pinned
verify_round.py --transcript chooses its checks from the file's own format field, so a file
relabelled as the web format is checked without the agreement signatures or the modulus and can
pass. The iPhone only ever exports cravage-transcript-2, so this command refuses anything else.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verify_round  # noqa: E402


def main(argv):
    if len(argv) != 2:
        print("usage: verify_transcript.py <cravage-transcript.json>")
        return 2
    try:
        with open(argv[1], encoding="utf-8") as f:
            t = json.load(f)
    except (OSError, ValueError) as e:
        print("FAIL: could not read the file as JSON (" + verify_round._clean(e) + ")")
        return 1
    if not isinstance(t, dict) or t.get("format") != verify_round.V2_FORMAT:
        print("FAIL: not a " + verify_round.V2_FORMAT + " file; the iPhone app exports only that format")
        return 1
    return verify_round._verify_transcript_v2(t)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
