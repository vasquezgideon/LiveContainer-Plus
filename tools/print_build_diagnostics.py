#!/usr/bin/env python3
"""Print actionable compiler diagnostics from a raw xcodebuild log.

Does not infer that a generic exit-65 build was caused by signing.  On a
failure with no explicit compiler errors, prints the end of the raw log.
"""
from pathlib import Path
import re
import sys

if len(sys.argv) < 2:
    sys.exit("usage: print_build_diagnostics.py build.log [xcodebuild_exit_code]")
log_path = Path(sys.argv[1])
if not log_path.is_file():
    sys.exit(f"Missing build log: {log_path}")
lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
result = int(sys.argv[2]) if len(sys.argv) >= 3 else 1
if result == 0:
    print(f"xcodebuild succeeded; {len(lines)} raw log lines retained in build-log artifact")
    sys.exit(0)

patterns = [
    re.compile(r"(?i)(?:^|[\s:])(?:fatal\s+)?error:") ,
    re.compile(r"(?i)\b(?:Command (?:SwiftCompile|SwiftEmitModule|CompileSwift|CompileC|Ld|PhaseScriptExecution)|CompileSwiftSources).*failed"),
    re.compile(r"(?i)^\*\* (?:ARCHIVE|BUILD) FAILED \*\*$"),
    re.compile(r"(?i)\b(?:No such module|failed to emit module|unable to open|codesign failed)\b"),
]
indices = [i for i, line in enumerate(lines) if any(p.search(line) for p in patterns)]
print(f"xcodebuild exit {result} — {len(lines)} log lines; {len(indices)} possible error markers")
if indices:
    # Show the first failures before cascading errors; show context and avoid
    # repeating overlapping ranges. GitHub's step summary will also use this.
    shown = set()
    for i in indices[:12]:
        print(f"\n--- Build log line {i + 1} ---")
        for j in range(max(0, i - 3), min(len(lines), i + 5)):
            if j not in shown:
                print(f"{j + 1:>6}: {lines[j][:700]}")
                shown.add(j)
else:
    print("No explicit compiler error matched. Last 90 unfiltered log lines:")
    start = max(0, len(lines) - 90)
    for i in range(start, len(lines)):
        print(f"{i+1:>6}: {lines[i][:700]}")
print("\nFull output: Actions > Artifacts > build-log > build.log")
