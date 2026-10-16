#!/usr/bin/env bash
#
# Builds CapsJump.app: a universal (arm64 + x86_64) release build of the app and the
# CLI, put into one bundle and signed.
#
#   Contents/MacOS/CapsJump     the app that receives capsjump:// links
#   Contents/Helpers/capsjump   the CLI (Homebrew links it onto PATH); it can't sit in
#                                   MacOS/ beside the app, because the Mac's case-insensitive
#                                   file system can't hold both names in one folder
#
# Usage: scripts/bundle.sh [--identity "<Developer ID Application: …>"] [--out <dir>]
#
# With --identity, both executables are signed with the hardened runtime and a secure
# timestamp, ready for notarization (scripts/notarize.sh). Without it the bundle is signed
# ad hoc, which is fine for trying a build, but macOS ties the Accessibility and Automation
# grants to an ad hoc signature's hash, so every rebuild asks for them again.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY=""
OUT="$ROOT/.build/bundle"

fail() {
  echo "bundle: $*" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --identity) IDENTITY="${2:?--identity needs a value}"; shift 2 ;;
    --out) OUT="${2:?--out needs a value}"; shift 2 ;;
    *) echo "usage: bundle.sh [--identity <name>] [--out <dir>]" >&2; exit 2 ;;
  esac
done

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION must be x.y.z, not \"$VERSION\""

build=(swift build --package-path "$ROOT" -c release --arch arm64 --arch x86_64)
"${build[@]}"
BIN="$("${build[@]}" --show-bin-path)"

APP="$OUT/CapsJump.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/CapsJumpApp" "$APP/Contents/MacOS/CapsJump"
cp "$BIN/capsjump" "$APP/Contents/Helpers/capsjump"
sed "s/@VERSION@/$VERSION/g" "$ROOT/packaging/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$ROOT/packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

for exe in "$APP/Contents/MacOS/CapsJump" "$APP/Contents/Helpers/capsjump"; do
  archs="$(lipo -archs "$exe")"
  [[ "$archs" == *x86_64* && "$archs" == *arm64* ]] || fail "$exe is not universal: $archs"
done

# Nested code first, the bundle last: the app's signature seals the CLI's.
if [ -n "$IDENTITY" ]; then
  sign=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
else
  sign=(codesign --force --options runtime --sign -)
fi
"${sign[@]}" --identifier ai.stigmer.capsjump.cli "$APP/Contents/Helpers/capsjump"
"${sign[@]}" --entitlements "$ROOT/packaging/CapsJump.entitlements" "$APP"
codesign --verify --strict --deep --verbose=1 "$APP"

echo "bundle: built $APP ($VERSION, ${IDENTITY:-ad hoc})"
