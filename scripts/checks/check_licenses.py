#!/usr/bin/env python3
from pathlib import Path
import sys
root = Path(__file__).resolve().parents[2]
expected = {"LICENSE_ChOma", "LICENSE_libgrabkernel2", "LICENSE_RootHideManagerApp", "LICENSE_XPF"}
found = set()
for base in [root / "lara", root / "lara" / "licenses"]:
    if not base.exists():
        continue
    for p in base.iterdir():
        if p.stem.startswith("LICENSE_") and p.suffix.lower() in {".md", ".txt"}:
            found.add(p.stem)
missing = expected - found
if missing:
    print("FAIL missing licenses:", ", ".join(sorted(missing)))
    sys.exit(1)
print("OK: expected license files present:", ", ".join(sorted(found)))
