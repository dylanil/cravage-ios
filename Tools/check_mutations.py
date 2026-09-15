#!/usr/bin/env python3
"""Require each listed mutation to compile and then fail an actual XCTest case.

Runs in an isolated source copy so another coding session never observes a mutant.
Build/test logs are retained under .build/mutations/. An error is never a caught guard.

    python3 Tools/check_mutations.py
    python3 Tools/check_mutations.py --suite app --destination 'platform=iOS Simulator,name=iPhone 17 Pro'
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
FAILED_CASE = re.compile(r"^Test Case '(.+)' failed \(", re.MULTILINE)
PASSED_CASE = re.compile(r"^Test Case '.+' passed \(", re.MULTILINE)


def command(args, work, log):
    try:
        with log.open("w") as output:
            result = subprocess.run(args, cwd=work, stdout=output, stderr=subprocess.STDOUT,
                                    timeout=600)
        return result.returncode
    except (OSError, subprocess.TimeoutExpired) as error:
        with log.open("a") as output:
            output.write(f"\nRunner error: {error}\n")
        return -1


def run_tests(work, logs, name, suite="core", destination=None):
    if suite == "app":
        options = ["-project", "Cravage.xcodeproj", "-scheme", "Cravage", "-destination", destination,
                   "-derivedDataPath", str(work / ".build/DerivedData"), "-parallel-testing-enabled", "NO",
                   "CODE_SIGNING_ALLOWED=NO"]
        build = ["xcodebuild", "build-for-testing", *options]
        test = ["xcodebuild", "test-without-building", *options]
    else:
        build = ["swift", "build", "--build-tests", "--package-path", "CravageCore"]
        test = ["swift", "test", "--skip-build", "--package-path", "CravageCore"]
    build_log = logs / f"{name}-build.log"
    if command(build, work, build_log) != 0:
        return "error", f"build failed; see {build_log}"
    test_log = logs / f"{name}-test.log"
    code = command(test, work, test_log)
    output = test_log.read_text(errors="replace")
    failures = FAILED_CASE.findall(output)
    if code > 0 and failures:
        return "failed", f"{', '.join(failures)}; see {test_log}"
    if code == 0 and not failures and PASSED_CASE.search(output):
        return "passed", str(test_log)
    return "error", f"no reliable test result; see {test_log}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=["core", "app"], default="core")
    parser.add_argument("--destination", help="xcodebuild simulator destination, required for the app suite")
    args = parser.parse_args()
    if args.suite == "app" and not args.destination:
        parser.error("--suite app requires --destination")
    mutations = json.loads((ROOT / "Tools/mutations.json").read_text())["mutations"]
    if any(m.get("suite", "core") not in ("core", "app") for m in mutations):
        parser.error("unknown mutation suite; expected core or app")
    mutations = [m for m in mutations if m.get("suite", "core") == args.suite]
    logs = ROOT / ".build/mutations" / str(time.time_ns())
    logs.mkdir(parents=True)
    print(f"Evidence: {logs}", flush=True)
    with tempfile.TemporaryDirectory(prefix="cravage-mutations-") as directory:
        work = Path(directory)
        shutil.copytree(ROOT / "CravageCore", work / "CravageCore",
                        ignore=shutil.ignore_patterns(".build", ".swiftpm"))
        if args.suite == "app":
            for directory in ["Cravage", "CravageTests", "Cravage.xcodeproj", "Config"]:
                shutil.copytree(ROOT / directory, work / directory,
                                ignore=shutil.ignore_patterns(".build", "xcuserdata", "Local.xcconfig"))
        status, detail = run_tests(work, logs, "baseline", args.suite, args.destination)
        if status != "passed":
            print(f"FAIL: the unmutated suite does not pass: {detail}")
            return 1
        problems = 0
        for index, mutation in enumerate(mutations):
            path = work / mutation["file"]
            original = path.read_text()
            count = original.count(mutation["find"])
            if count != 1:
                print(f"DRIFT: '{mutation['name']}' find text occurs {count} times")
                problems += 1
                continue
            try:
                path.write_text(original.replace(mutation["find"], mutation["replace"]))
                status, detail = run_tests(work, logs, f"mutation-{index + 1}", args.suite, args.destination)
            finally:
                path.write_text(original)
            if status == "failed":
                print(f"caught: {mutation['name']}: {detail}", flush=True)
            else:
                kind = "SURVIVED" if status == "passed" else "ERROR"
                print(f"{kind}: {mutation['name']}: {detail}", flush=True)
                problems += 1
        if problems:
            print(f"FAIL: {problems} of {len(mutations)} mutations not caught or drifted")
            return 1
    print(f"PASS: all {len(mutations)} mutations caught")
    return 0


if __name__ == "__main__":
    sys.exit(main())
