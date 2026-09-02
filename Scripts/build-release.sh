#!/bin/zsh
# Build a Release dict8.app and install it to /Applications.
#
# Replaces the Xcode Product → Archive flow for daily use. The app is quit
# first so only one dict8 process ever runs; permissions may need a one-time
# re-grant after replacing the installed bundle (see docs/INSTALL.md).
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

PROJECT="dict8/dict8.xcodeproj"
DESTINATION="platform=macOS,arch=arm64"

echo "==> Building Release"
xcodebuild -project "$PROJECT" -scheme dict8 -configuration Release -destination "$DESTINATION" -quiet build

BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme dict8 -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/TARGET_BUILD_DIR/{print $2}' | grep '/Build/Products/Release$' | head -1)
if [ -z "$BUILD_DIR" ] || [ ! -d "$BUILD_DIR/dict8.app" ]; then
  echo "error: Release build product not found" >&2
  exit 1
fi

if pgrep -x dict8 >/dev/null 2>&1; then
  echo "==> Quitting running dict8"
  osascript -e 'quit app "dict8"' >/dev/null 2>&1 || true
  sleep 2
fi
if pgrep -x dict8 >/dev/null 2>&1; then
  echo "error: dict8 is still running; quit it and retry" >&2
  exit 1
fi

echo "==> Installing to /Applications"
ditto "$BUILD_DIR/dict8.app" /Applications/dict8.app

echo "==> Launching /Applications/dict8.app"
open /Applications/dict8.app

echo "Done. If Accessibility or Microphone prompts reappear, run:"
echo "  tccutil reset Accessibility com.xehl.dict8 && tccutil reset Microphone com.xehl.dict8"
echo "then re-grant both in System Settings and relaunch dict8."
