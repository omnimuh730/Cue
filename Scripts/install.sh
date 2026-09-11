#!/bin/zsh
# Build Cue (Release) inside the project folder and install it to /Applications.
# Personal, single-machine install: no notarization, signed with the project's
# development team so Accessibility / Screen Recording grants survive rebuilds.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/Build"
CONFIG="${1:-Release}"
DEST="${CUE_INSTALL_DIR:-/Applications}"

echo "→ Building Cue ($CONFIG) into $BUILD"
xcodebuild \
  -project "$ROOT/Cue.xcodeproj" \
  -scheme Cue \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD/DerivedData" \
  SYMROOT="$BUILD/Products" \
  OBJROOT="$BUILD/Intermediates.noindex" \
  build \
  | grep -E "error:|warning: .*Cue/.*\.swift|BUILD" || true

APP="$BUILD/Products/$CONFIG/Cue.app"
[[ -d "$APP" ]] || { echo "✗ $APP not found; build failed." >&2; exit 1; }

echo "→ Installing to $DEST/Cue.app"
pkill -x Cue 2>/dev/null || true
sleep 0.5
rm -rf "$DEST/Cue.app"
ditto "$APP" "$DEST/Cue.app"
xattr -dr com.apple.quarantine "$DEST/Cue.app" 2>/dev/null || true

echo "→ Launching"
open "$DEST/Cue.app"
echo "✓ Installed $(defaults read "$DEST/Cue.app/Contents/Info.plist" CFBundleShortVersionString) at $DEST/Cue.app"
