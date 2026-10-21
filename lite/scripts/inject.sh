#!/usr/bin/env bash
# Adds LCPlus.dylib to an IPA.
# usage: inject.sh <in.ipa> <LCPlus.dylib> <out.ipa>
set -euo pipefail
IN="$1"; DYLIB="$2"; OUT="$3"
HERE="$(cd "$(dirname "$0")" && pwd)"
W=$(mktemp -d)

unzip -q "$IN" -d "$W"
APP=$(ls -d "$W"/Payload/*.app | head -1)
EXE=$(python3 -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb"))["CFBundleExecutable"])' "$APP/Info.plist")
echo "app: $(basename "$APP")  executable: $EXE"

mkdir -p "$APP/Frameworks"
cp "$DYLIB" "$APP/Frameworks/LCPlus.dylib"
rm -rf "$APP/_CodeSignature"
python3 "$HERE/inject_dylib.py" "$APP/$EXE" "@executable_path/Frameworks/LCPlus.dylib"
if command -v otool >/dev/null 2>&1; then
  otool -L "$APP/$EXE" | grep -q LCPlus.dylib || { echo "injection failed: load command not found"; exit 1; }
fi

OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
rm -f "$OUT_ABS"
(cd "$W" && zip -qry "$OUT_ABS" Payload)
echo "wrote $OUT_ABS"
