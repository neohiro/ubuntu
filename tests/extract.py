#!/usr/bin/env python3
"""Extract named functions from ubuntuinstall.sh for the test harness."""
import re
import sys
from pathlib import Path

src = Path(sys.argv[1]).read_text(encoding="utf-8")
names = sys.argv[2].split(",")
out = []
for name in names:
    pat = rf"^{re.escape(name)}\(\) \{{"
    m = re.search(pat, src, re.M)
    if not m:
        out.append(f"# MISSING: {name}")
        continue
    start = m.start()
    depth = 0
    i = m.end() - 1
    end = None
    while i < len(src):
        c = src[i]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                end = i + 1
                break
        i += 1
    if end is None:
        out.append(f"# UNCLOSED: {name}")
        continue
    out.append(f"# --- {name} ---")
    out.append(src[start:end])
# Write to stdout as UTF-8 to avoid Windows cp1252 codec crashes
sys.stdout.buffer.write("\n\n".join(out).encode("utf-8"))
