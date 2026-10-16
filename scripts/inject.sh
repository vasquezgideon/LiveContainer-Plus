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

# --- LiveContainer Plus naming ---
# Main app display name
PLIST="$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName LiveContainer Plus' "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string LiveContainer Plus' "$PLIST"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName LiveContainer Plus' "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c 'Add :CFBundleName string LiveContainer Plus' "$PLIST"

# Rewrite every CFBundleIdentifier under the .app so extensions keep the required parent prefix.
# e.g. com.kdt.livecontainer.ZFUB4BJRCX          → com.kdt.livecontainer.plus.ZFUB4BJRCX
#      com.kdt.livecontainer.LiveProcess         → com.kdt.livecontainer.plus.LiveProcess
#      com.kdt.livecontainer.LiveProcess.xxx     → com.kdt.livecontainer.plus.LiveProcess.xxx
rewrite_bid() {
  local p="$1"
  local old
  old=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$p" 2>/dev/null || true)
  [[ -z "$old" ]] && return
  if [[ "$old" == com.kdt.livecontainer* && "$old" != com.kdt.livecontainer.plus* ]]; then
    local new="${old/com.kdt.livecontainer/com.kdt.livecontainer.plus}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $new" "$p"
    echo "  $old → $new  ($(basename "$(dirname "$p")"))"
  fi
}

echo "rewriting bundle IDs:"
# Main Info.plist first
rewrite_bid "$PLIST"
# Every nested Info.plist (PlugIns, Extensions, Watch, Frameworks that carry one, etc.)
while IFS= read -r -d '' plist; do
  rewrite_bid "$plist"
done < <(find "$APP" -name Info.plist -print0)

# Also rewrite any embedded.mobileprovision / entitlement-related strings that still
# reference the old prefix is unnecessary for SideStore (it re-signs), but we must
# keep extension IDs under the parent prefix so IXPlaceholder accepts the IPA.

NEW_BID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")
echo "display name: LiveContainer Plus  main bundle id: $NEW_BID"

OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
rm -f "$OUT_ABS"
(cd "$W" && zip -qry "$OUT_ABS" Payload)
echo "wrote $OUT_ABS"
