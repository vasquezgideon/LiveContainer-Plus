#!/usr/bin/env bash
# usage: inject.sh <in.ipa> <LCPlus.dylib> <out.ipa> <insert_dylib binary>
set -euo pipefail
IN="$1"; DYLIB="$2"; OUT="$3"; INSERT="$4"
W=$(mktemp -d)
unzip -q "$IN" -d "$W"
APP=$(ls -d "$W"/Payload/*.app | head -1)
EXE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")
echo "app: $(basename "$APP")  executable: $EXE"
mkdir -p "$APP/Frameworks"
cp "$DYLIB" "$APP/Frameworks/LCPlus.dylib"
rm -rf "$APP/_CodeSignature"
"$INSERT" --strip-codesig --inplace --all-yes "@executable_path/Frameworks/LCPlus.dylib" "$APP/$EXE"
otool -L "$APP/$EXE" | grep -q LCPlus.dylib || { echo "injection failed: load command not found"; exit 1; }
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
rm -f "$OUT_ABS"
(cd "$W" && zip -qry "$OUT_ABS" Payload)
echo "wrote $OUT_ABS"
