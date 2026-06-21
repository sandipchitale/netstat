#!/bin/bash
#
# Builds the release binary and assembles netstat.app from the inputs in
# packaging/. The netstat.app bundle is a build artifact (git-ignored) and is
# fully recreated by this script.
#
# Usage:
#   ./build-app.sh            # build + assemble ./netstat.app
#   ./build-app.sh --install  # also copy the bundle into /Applications
#   ./build-app.sh --run      # also (re)launch the app afterwards
#
set -euo pipefail

cd "$(dirname "$0")"

APP="netstat.app"
BINARY_NAME="netstat"          # must match CFBundleExecutable in Info.plist

INSTALL=false
RUN=false
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=true ;;
    --run)     RUN=true ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

echo "==> Building release binary"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/${BINARY_NAME}"

echo "==> Assembling ${APP}"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"
cp "packaging/Info.plist"  "${APP}/Contents/Info.plist"
cp "packaging/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
cp "${BIN_PATH}"           "${APP}/Contents/MacOS/${BINARY_NAME}"
chmod +x "${APP}/Contents/MacOS/${BINARY_NAME}"
echo "    built ${APP}"

if [ "${INSTALL}" = true ]; then
  echo "==> Installing to /Applications"
  osascript -e 'tell application "TCP Port Monitor" to quit' 2>/dev/null || true
  pkill -x "${BINARY_NAME}" 2>/dev/null || true
  sleep 1
  rm -rf "/Applications/${APP}"
  cp -R "${APP}" "/Applications/${APP}"
  echo "    installed /Applications/${APP}"
fi

if [ "${RUN}" = true ]; then
  if [ "${INSTALL}" = true ]; then
    open "/Applications/${APP}"
  else
    open "${APP}"
  fi
  echo "==> Launched"
fi
