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

# Rename to LiveContainer Plus with a distinct bundle ID so it can sit next to stock LC
PLIST="$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName LiveContainer Plus' "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string LiveContainer Plus' "$PLIST"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName LiveContainer Plus' "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Add :CFBundleName string LiveContainer Plus' "$PLIST"
# Keep the team-suffix style if present (e.g. com.kdt.livecontainer.TXXXX) → com.kdt.livecontainer.plus.TXXXX
ORIG_BID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")
if [[ "$ORIG_BID" == com.kdt.livecontainer* ]]; then
  NEW_BID="${ORIG_BID/com.kdt.livecontainer/com.kdt.livecontainer.plus}"
else
  NEW_BID="com.kdt.livecontainer.plus"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $NEW_BID" "$PLIST"
echo "display name: LiveContainer Plus  bundle id: $NEW_BID"

OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
rm -f "$OUT_ABS"
(cd "$W" && zip -qry "$OUT_ABS" Payload)
echo "wrote $OUT_ABS"
