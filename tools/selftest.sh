#!/usr/bin/env bash
# Local sanity check (Linux/macOS, no Xcode needed): fetches LiveContainer stable + nightly, applies every
# LC Plus group and syntax-parses all touched Swift/Objective-C files.
#   pip install tree-sitter tree-sitter-swift tree-sitter-objc   (add --break-system-packages if pip asks)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
REPO="${REPO:-LiveContainer/LiveContainer}"
tag=$(git ls-remote --tags --refs "https://github.com/$REPO" | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -V | tail -1)
for ref in "$tag" main; do
  echo "=== $REPO @ $ref"
  git clone -q --depth 1 --branch "$ref" "https://github.com/$REPO" "$TMP/clean-$ref"
  cp -r "$TMP/clean-$ref" "$TMP/work-$ref"
  python3 "$HERE/patcher/apply.py" --lc "$TMP/work-$ref" --strict
  python3 "$HERE/tools/syntax_check.py" "$TMP/work-$ref" "$TMP/clean-$ref" | tail -1
done
rm -rf "$TMP"
