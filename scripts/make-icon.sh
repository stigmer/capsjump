#!/usr/bin/env bash
#
# Renders packaging/icon.svg into packaging/AppIcon.icns, the icon scripts/bundle.sh puts
# in CapsJump.app, and packaging/menubar.svg into MenuBarIcon.png and MenuBarIcon@2x.png,
# the menu-bar image beside it. The .icns is committed so a build needs no SVG renderer; rerun this
# after changing the SVG. Needs rsvg-convert (brew install librsvg) and macOS's iconutil.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$ROOT/packaging/icon.svg"
ICNS="$ROOT/packaging/AppIcon.icns"

command -v rsvg-convert >/dev/null || { echo "make-icon: rsvg-convert not found; brew install librsvg" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SET="$WORK/AppIcon.iconset"
mkdir "$SET"
for size in 16 32 128 256 512; do
  rsvg-convert -w "$size" -h "$size" "$SVG" -o "$SET/icon_${size}x${size}.png"
  rsvg-convert -w $((size * 2)) -h $((size * 2)) "$SVG" -o "$SET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$SET" -o "$ICNS"
echo "make-icon: wrote $ICNS"

MENUBAR="$ROOT/packaging/menubar.svg"
rsvg-convert -w 18 -h 18 "$MENUBAR" -o "$ROOT/packaging/MenuBarIcon.png"
rsvg-convert -w 36 -h 36 "$MENUBAR" -o "$ROOT/packaging/MenuBarIcon@2x.png"
echo "make-icon: wrote $ROOT/packaging/MenuBarIcon.png and MenuBarIcon@2x.png"
