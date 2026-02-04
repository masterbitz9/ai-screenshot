#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/AiShot/Info.plist"
README="$ROOT_DIR/Readme.md"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Info.plist not found at $INFO_PLIST" >&2
  exit 1
fi

if [[ ! -f "$README" ]]; then
  echo "Readme.md not found at $README" >&2
  exit 1
fi

version=$(defaults read "$INFO_PLIST" CFBundleShortVersionString)
build=$(defaults read "$INFO_PLIST" CFBundleVersion)

if [[ -z "$version" || -z "$build" ]]; then
  echo "Failed to read version/build from Info.plist" >&2
  exit 1
fi

awk -v ver="$version" -v build="$build" '
  BEGIN { in_version = 0 }
  /^## Version$/ { in_version = 1; print; next }
  in_version && /^- App version:/ { print "- App version: " ver; next }
  in_version && /^- Build:/ { print "- Build: " build; in_version = 0; next }
  { print }
' "$README" > "$README.tmp"

mv "$README.tmp" "$README"

echo "Updated Readme.md to version $version (build $build)."
