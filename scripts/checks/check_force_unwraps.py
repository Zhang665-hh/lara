#!/usr/bin/env python3
"""Fail on new high-risk force-unwrap / try! patterns in app Swift sources."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[2]
scan_root = root / "lara"
# Keep this list short and intentional — known-safe literals only.
allow_substrings = {
    # Bridging / UIKit patterns that are conventionally force-unwrapped.
    "UIApplication.shared",
}

patterns = [
    (re.compile(r"\btry!\b"), "try!"),
    (re.compile(r"\bas!\b"), "as!"),
    (re.compile(r"URL\s*\(\s*string\s*:\s*[^\)]+\)\s*!(?!=)"), "URL(string:)!"),
    (re.compile(r"Bundle\.main\.bundleIdentifier\s*!"), "Bundle.main.bundleIdentifier!"),
    (re.compile(r"\bfatalError\s*\("), "fatalError("),
    (re.compile(r"\bpreconditionFailure\s*\("), "preconditionFailure("),
    (re.compile(r"\.(first|last)\s*!"), ".first!/.last!"),
    (re.compile(r"\bbaseAddress\s*!"), "baseAddress!"),
]

skip_dirs = {".git", "build", "DerivedData", "PartyUI"}
hits = []

for path in scan_root.rglob("*.swift"):
    if any(part in skip_dirs for part in path.parts):
        continue
    try:
        text = path.read_text(errors="ignore")
    except Exception:
        continue
    for i, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        if any(a in line for a in allow_substrings):
            continue
        for cre, label in patterns:
            if cre.search(line):
                rel = path.relative_to(root)
                hits.append(f"{rel}:{i}: {label}: {stripped}")

if hits:
    print("High-risk force unwrap / try! patterns found:")
    for h in hits:
        print(" ", h)
    sys.exit(1)

print("force-unwrap check passed")
