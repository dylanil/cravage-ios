#!/usr/bin/env bash
# CI: the privacy manifest (Cravage/Resources/PrivacyInfo.xcprivacy) declares every required-reason
# API category the app's code uses, claims no tracking and no collected data, and, given a built
# app, is inside it. Apple can refuse an upload whose manifest misses a category it finds in use.
#
# Usage: Tools/check_privacy_manifest.sh [built Cravage.app]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"

python3 - "$ROOT" "${1:-}" <<'EOF'
import pathlib, plistlib, re, sys

root, app = pathlib.Path(sys.argv[1]), sys.argv[2]
manifest_path = root / "Cravage/Resources/PrivacyInfo.xcprivacy"
manifest = plistlib.loads(manifest_path.read_bytes())
failures = []

if manifest.get("NSPrivacyTracking") is not False or manifest.get("NSPrivacyTrackingDomains"):
    failures.append("the manifest must claim no tracking and no tracking domains")
if manifest.get("NSPrivacyCollectedDataTypes"):
    failures.append("the manifest lists collected data; the App Store label says Data Not Collected")
declared = {entry["NSPrivacyAccessedAPIType"]: entry.get("NSPrivacyAccessedAPITypeReasons", [])
            for entry in manifest.get("NSPrivacyAccessedAPITypes", [])}
for category, reasons in declared.items():
    if not reasons:
        failures.append(f"{category} is declared without a reason")

# Apple's required-reason API categories and the calls in each that Swift code here could reach.
patterns = {
    "NSPrivacyAccessedAPICategoryUserDefaults": r"\bUserDefaults\b|@AppStorage\b",
    "NSPrivacyAccessedAPICategoryFileTimestamp":
        r"\bcreationDate\b|\bmodificationDate\b|contentModificationDate|attributesOfItem|getattrlist|\bf?stat\(",
    "NSPrivacyAccessedAPICategorySystemBootTime": r"\bsystemUptime\b|mach_absolute_time",
    "NSPrivacyAccessedAPICategoryDiskSpace":
        r"volumeAvailableCapacity|volumeTotalCapacity|systemFreeSize|systemSize\b|\bstatv?fs\(",
    "NSPrivacyAccessedAPICategoryActiveKeyboards": r"activeInputModes",
}
sources = [p for d in ("Cravage", "CravageCore/Sources") for p in (root / d).rglob("*.swift")]
for category, pattern in patterns.items():
    users = sorted({str(p.relative_to(root)) for p in sources if re.search(pattern, p.read_text())})
    if users and category not in declared:
        failures.append(f"{category} is used ({', '.join(users)}) but not declared")

if app:
    if not (pathlib.Path(app) / "PrivacyInfo.xcprivacy").is_file():
        failures.append(f"{app} does not contain PrivacyInfo.xcprivacy")

if failures:
    print("Privacy manifest check failed:", *failures, sep="\n  ", file=sys.stderr)
    sys.exit(1)
print("Privacy manifest: declares " + ", ".join(sorted(declared)) + ("; present in the app" if app else ""))
EOF
