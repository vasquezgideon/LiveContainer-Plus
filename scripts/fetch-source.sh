#!/usr/bin/env bash
# Fetches the LiveContainer source tree into ./lc (override with OUT_DIR).
#
#   SOURCE        official | mirror | fork | release | url
#   CHANNEL       nightly | stable           (official, mirror, fork)
#   FORK_REPO     owner/name                 (fork)
#   REF_INPUT     branch, tag or commit      (official, mirror, fork)
#   RELEASE_TAG   release holding the zip    (release; empty = newest release that has a .zip asset)
#   SOURCE_URL    https link to a .zip       (url)
#
# Archives (release, url) may be incomplete, for example GitHub's "Download ZIP" leaves out submodules. Missing
# submodules and build scripts are fetched at the versions pinned by the official LiveContainer repository.
# Writes SRC_DESC and REF_LABEL to $GITHUB_ENV.
set -euo pipefail

OFFICIAL_REPO="LiveContainer/LiveContainer"
OUT_DIR="${OUT_DIR:-lc}"
ENV_FILE="${GITHUB_ENV:-/dev/null}"

note() { echo "$*" >&2; }
fail() { echo "::error::$*" >&2; exit 1; }
export_env() { echo "$1=$2" >> "$ENV_FILE"; }

default_branch() {
  git ls-remote --symref "https://github.com/$1" HEAD | awk '/^ref:/ {sub("refs/heads/","",$2); print $2; exit}'
}

# Latest release tag of a repository (GitHub API, falling back to the highest version-like tag)
latest_release_tag() {
  local tag
  tag=$(gh api "repos/$1/releases/latest" --jq .tag_name 2>/dev/null || true)
  [ -n "$tag" ] || tag=$(git ls-remote --tags --refs "https://github.com/$1" | awk -F/ '{print $NF}' | grep -E '^[0-9]+(\.[0-9]+)*$' | sort -V | tail -1 || true)
  echo "$tag"
}

# Ref of the official repository whose pins complete an incomplete source tree
official_pin_ref() {
  local ref=""
  if [ "${CHANNEL:-nightly}" = "stable" ]; then
    ref=$(latest_release_tag "$OFFICIAL_REPO")
  fi
  [ -n "$ref" ] || ref=$(default_branch "$OFFICIAL_REPO")
  echo "$ref"
}

# Tree-only checkout of the official repository at $1: lets us read the submodule versions it pins
PIN_DIR=""
pin_tree() {
  if [ -z "$PIN_DIR" ]; then
    PIN_DIR=$(mktemp -d)
    git init -q "$PIN_DIR"
    git -C "$PIN_DIR" remote add origin "https://github.com/$OFFICIAL_REPO"
    git -C "$PIN_DIR" fetch -q --depth 1 --filter=blob:none origin "$1" >&2 || { PIN_DIR=""; return 1; }
  fi
}
pinned_sha() {   # submodule path -> commit pinned by the official repository
  git -C "$PIN_DIR" ls-tree FETCH_HEAD "$1" 2>/dev/null | awk '$2 == "commit" {print $3}'
}

fetch_submodule() {
  local name=$1 path=$2 pin=$3 url sha=""
  url=$(git config -f "$OUT_DIR/.gitmodules" --get "submodule.$name.url" | sed -E 's#^git@github.com:#https://github.com/#; s#^ssh://git@github.com/#https://github.com/#')
  local listed=""
  if pin_tree "$pin"; then
    sha=$(pinned_sha "$path")
    listed=$(git -C "$PIN_DIR" ls-tree FETCH_HEAD "$path" 2>/dev/null || true)
  fi
  rm -rf "${OUT_DIR:?}/$path"
  mkdir -p "$OUT_DIR/$path"
  git init -q "$OUT_DIR/$path"
  git -C "$OUT_DIR/$path" remote add origin "$url"
  if [ -n "$sha" ] && git -C "$OUT_DIR/$path" fetch -q --depth 1 origin "$sha"; then
    git -C "$OUT_DIR/$path" checkout -q FETCH_HEAD
    note "  $path: ${sha:0:9} (pinned by $OFFICIAL_REPO @ $pin)"
  else
    if [ -n "$listed" ]; then
      echo "::warning::could not fetch the pinned version of $path; using the default branch of $url" >&2
    else
      note "  $path: not pinned by $OFFICIAL_REPO @ $pin; using the default branch of $url"
    fi
    git -C "$OUT_DIR/$path" fetch -q --depth 1 origin HEAD || fail "cannot fetch $url"
    git -C "$OUT_DIR/$path" checkout -q FETCH_HEAD
  fi
  if [ -f "$OUT_DIR/$path/.gitmodules" ]; then
    git -C "$OUT_DIR/$path" submodule update --init --recursive >&2
  fi
}

# Fills in whatever an archive does not contain
complete_source() {
  local pin="" key path name tmp
  if [ -d "$OUT_DIR/.git" ] && [ -f "$OUT_DIR/.gitmodules" ]; then   # an archived clone: let git do the work
    git -C "$OUT_DIR" submodule update --init --recursive >&2 || true
  fi
  if [ -f "$OUT_DIR/.gitmodules" ]; then
    while read -r key path; do
      name=${key#submodule.}
      name=${name%.path}
      if [ -z "$(ls -A "$OUT_DIR/$path" 2>/dev/null)" ]; then
        [ -n "$pin" ] || { pin=$(official_pin_ref); note "Completing the source with submodules from $OFFICIAL_REPO @ $pin"; }
        fetch_submodule "$name" "$path" "$pin"
      fi
    done < <(git config -f "$OUT_DIR/.gitmodules" --get-regexp '^submodule\..*\.path$')
  fi
  if [ ! -f "$OUT_DIR/.github/build_github.sh" ]; then
    [ -n "$pin" ] || pin=$(official_pin_ref)
    note "Build scripts are missing; fetching .github from $OFFICIAL_REPO @ $pin"
    tmp=$(mktemp -d)
    curl -fsSL "https://github.com/$OFFICIAL_REPO/archive/$pin.tar.gz" -o "$tmp/official.tar.gz"
    tar -xzf "$tmp/official.tar.gz" -C "$tmp"
    mkdir -p "$OUT_DIR/.github"
    ( cd "$tmp"/*/.github && find . -type f ) | while read -r f; do
      if [ ! -e "$OUT_DIR/.github/$f" ]; then
        mkdir -p "$(dirname "$OUT_DIR/.github/$f")"
        cp "$tmp"/*/.github/"$f" "$OUT_DIR/.github/$f"
      fi
    done
    rm -rf "$tmp"
  fi
}

# Unpacks a .zip into $OUT_DIR (a single top-level folder is unwrapped) and completes it
use_archive() {
  local entries top
  rm -rf lc_unzip "$OUT_DIR"
  mkdir lc_unzip
  unzip -q "$1" -d lc_unzip
  rm -rf lc_unzip/__MACOSX
  entries=$(ls -A lc_unzip | wc -l | tr -d ' ')
  top=$(ls -A lc_unzip | head -1)
  if [ "$entries" = "1" ] && [ -d "lc_unzip/$top" ]; then
    mv "lc_unzip/$top" "$OUT_DIR"
    rmdir lc_unzip 2>/dev/null || true
  else
    mv lc_unzip "$OUT_DIR"
  fi
  [ -d "$OUT_DIR/LiveContainer.xcodeproj" ] || fail "the archive does not look like a LiveContainer source tree (LiveContainer.xcodeproj not found)"
  complete_source
}

# Finds the zip attached to a release of this repository; prints "<tag>|<file>"
release_zip() {
  local tag="${RELEASE_TAG:-}" t file
  if [ -z "$tag" ]; then
    for t in $(gh release list --repo "$GITHUB_REPOSITORY" --limit 50 --json tagName --jq '.[].tagName'); do
      if gh release view "$t" --repo "$GITHUB_REPOSITORY" --json assets --jq '.assets[].name' | grep -qiE '\.zip$'; then
        tag=$t
        break
      fi
    done
  fi
  [ -n "$tag" ] || fail "no release of $GITHUB_REPOSITORY has a .zip asset. Create a release and attach your LiveContainer source as source.zip."
  rm -rf dl
  mkdir -p dl
  gh release download "$tag" --repo "$GITHUB_REPOSITORY" --pattern '*.zip' --dir dl >&2 || true
  file=$(ls dl/source*.zip 2>/dev/null | head -1 || true)
  [ -n "$file" ] || file=$(ls dl/*.zip 2>/dev/null | head -1 || true)
  [ -n "$file" ] || fail "release $tag has no .zip asset"
  echo "$tag|$file"
}

main() {
  local source="${SOURCE:-official}" repo ref found tag file
  rm -rf "$OUT_DIR"
  case "$source" in
    release)
      found=$(release_zip) || exit 1
      tag=${found%%|*}
      file=${found#*|}
      note "Using $(basename "$file") from release $tag"
      use_archive "$file"
      export_env SRC_DESC "$(basename "$file") from release $tag"
      export_env REF_LABEL "custom"
      ;;
    url)
      case "${SOURCE_URL:-}" in https://*) ;; *) fail "source_url must be an https link" ;; esac
      curl -fL --retry 3 -o source.zip "$SOURCE_URL"
      use_archive source.zip
      export_env SRC_DESC "source archive ($SOURCE_URL)"
      export_env REF_LABEL "custom"
      ;;
    official|mirror|fork)
      case "$source" in
        official) repo="LiveContainer/LiveContainer" ;;
        mirror)   repo="LiveContainerMirror/LiveContainer" ;;
        fork)     repo="${FORK_REPO:-}" ;;
      esac
      echo "$repo" | grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || fail "'$repo' is not a valid owner/name"
      ref=$(default_branch "$repo")
      [ -n "$ref" ] || fail "cannot reach https://github.com/$repo"
      if [ -n "${REF_INPUT:-}" ]; then
        ref="$REF_INPUT"
      elif [ "${CHANNEL:-nightly}" = "stable" ]; then
        found=$(latest_release_tag "$repo")
        if [ -n "$found" ]; then ref="$found"; else echo "::warning::$repo has no stable release; using $ref" >&2; fi
      fi
      note "Fetching $repo @ $ref"
      git init -q "$OUT_DIR"
      git -C "$OUT_DIR" remote add origin "https://github.com/$repo"
      git -C "$OUT_DIR" fetch -q --depth 1 origin "$ref"
      git -C "$OUT_DIR" checkout -q FETCH_HEAD
      git -C "$OUT_DIR" submodule update --init --recursive >&2
      export_env SRC_DESC "$repo @ $ref ($(git -C "$OUT_DIR" rev-parse --short HEAD))"
      export_env REF_LABEL "$(echo "$ref" | tr '/' '-')"
      ;;
    *) fail "unknown source '$source'" ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
