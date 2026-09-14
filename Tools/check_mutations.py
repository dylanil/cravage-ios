#!/usr/bin/env python3
"""Mutation gate: every guard listed in Tools/mutations.json must be caught by the test suite.

For each entry, replace `find` (which must occur exactly once) with `replace` in `file`, run
`swift test --package-path CravageCore`, and require it to FAIL. The file is always restored.
A clean run must pass first. Exits non-zero if any mutation survives or any `find` has drifted.

    python3 Tools/check_mutations.py
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run_tests():
    result = subprocess.run(["swift", "test", "--package-path", "CravageCore"], cwd=ROOT,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return result.returncode == 0


def main():
    with open(os.path.join(ROOT, "Tools", "mutations.json"), encoding="utf-8") as f:
        mutations = json.load(f)["mutations"]
    if not run_tests():
        print("FAIL: the unmutated suite does not pass")
        return 1
    problems = 0
    for m in mutations:
        path = os.path.join(ROOT, m["file"])
        with open(path, encoding="utf-8") as f:
            original = f.read()
        count = original.count(m["find"])
        if count != 1:
            print(f"DRIFT: '{m['name']}' find text occurs {count} times in {m['file']}; update Tools/mutations.json")
            problems += 1
            continue
        try:
            with open(path, "w", encoding="utf-8") as f:
                f.write(original.replace(m["find"], m["replace"]))
            survived = run_tests()
        finally:
            with open(path, "w", encoding="utf-8") as f:
                f.write(original)
        if survived:
            print(f"SURVIVED: '{m['name']}' - no test fails when this guard is removed")
            problems += 1
        else:
            print(f"caught: {m['name']}")
    if problems:
        print(f"FAIL: {problems} of {len(mutations)} mutations not caught or drifted")
        return 1
    print(f"PASS: all {len(mutations)} mutations caught")
    return 0


if __name__ == "__main__":
    sys.exit(main())
