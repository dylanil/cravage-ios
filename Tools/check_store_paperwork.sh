#!/usr/bin/env bash
# CI: docs/APP_STORE.md, the paperwork typed into App Store Connect, agrees with the code on the
# values Apple makes permanent or matches exactly: the unlock's product ID and the version.
# A product ID cannot be changed once created, so a mismatch has to be caught before then.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"

python3 - "$ROOT" <<'EOF'
import json, pathlib, re, sys

root = pathlib.Path(sys.argv[1])
paperwork = (root / "docs/APP_STORE.md").read_text()
failures = []

code_id = re.search(r'unlockProductID\s*=\s*"([^"]+)"', (root / "Cravage/Store/StoreManager.swift").read_text()).group(1)
storekit_ids = [p["productID"] for p in json.loads((root / "Config/Cravage.storekit").read_text()).get("products", [])]
paper_id = re.search(r"^\| Product ID \| `([^`]+)`", paperwork, re.M)
if storekit_ids != [code_id]:
    failures.append(f"Config/Cravage.storekit lists {storekit_ids}; the app asks for {code_id}")
if not paper_id or paper_id.group(1) != code_id:
    failures.append(f"APP_STORE.md's Product ID is {paper_id.group(1) if paper_id else 'missing'}; the app asks for {code_id}")

code_version = re.search(r'CFBundleShortVersionString:\s*"([^"]+)"', (root / "project.yml").read_text()).group(1)
paper_version = re.search(r"^\| Version \| ([^ |]+)", paperwork, re.M)
if not paper_version or paper_version.group(1) != code_version:
    failures.append(f"APP_STORE.md's Version is {paper_version.group(1) if paper_version else 'missing'}; project.yml has {code_version}")

if failures:
    print("Store paperwork disagrees with the code:", *failures, sep="\n  ", file=sys.stderr)
    sys.exit(1)
print(f"Store paperwork matches the code: product {code_id}, version {code_version}")
EOF
