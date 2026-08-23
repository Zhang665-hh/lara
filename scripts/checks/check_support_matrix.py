#!/usr/bin/env python3
"""Validate isunsupported.swift encodes the README support matrix."""
from pathlib import Path
import sys

src = Path("/workspace/lara/funcs/isunsupported.swift").read_text()

required_snippets = [
    ('block iOS < 16', 'majorVersion < 16'),
    ('block iOS 18.7.2+', 'patchVersion >= 2'),
    ('block iOS 19-25', 'majorVersion >= 19 && v.majorVersion <= 25'),
    ('block iOS > 26', 'majorVersion > 26'),
    ('block iOS 26.1+', 'minorVersion > 0'),
    ('block iOS 26.0.2+', 'patchVersion > 1'),
    ('block MIE devices', 'hasmie()'),
]

failed = []
for name, snippet in required_snippets:
    if snippet not in src:
        failed.append(name)

if failed:
    print("FAIL missing:", ", ".join(failed))
    sys.exit(1)
print("OK: isunsupported.swift matches documented support matrix")
