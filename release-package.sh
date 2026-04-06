#!/usr/bin/env bash
# Build a distributable .app from the Swift Package (DropZone/) release binary.
# Writes: releases/Notch Pocket-<CFBundleShortVersionString>.app (from Info.plist)
# Requires full Xcode toolchain (not CLT-only for some setups).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT}/DropZone"
RELEASES_DIR="${RELEASES_DIR:-${ROOT}/releases}"

EXECUTABLE="DropZone"
INFO_PLIST="${PKG_DIR}/Info.plist"
APP_BASE_NAME="${APP_BASE_NAME:-Notch Pocket}"

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "error: missing ${INFO_PLIST}" >&2
  exit 1
fi

if [[ -n "${VERSION_OVERRIDE:-}" ]]; then
  VERSION="${VERSION_OVERRIDE}"
else
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || true)"
fi
if [[ -z "${VERSION}" ]]; then
  echo "error: could not read CFBundleShortVersionString from ${INFO_PLIST}" >&2
  exit 1
fi

OUTPUT_NAME="${APP_BASE_NAME}-${VERSION}.app"
if [[ -n "${APP_NAME:-}" ]]; then
  # Full bundle name only (e.g. APP_NAME="Custom.app") — placed under releases/
  OUTPUT_NAME="${APP_NAME}"
fi

mkdir -p "${RELEASES_DIR}"

cd "$PKG_DIR"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="${BIN_DIR}/${EXECUTABLE}"

if [[ ! -f "$BIN" ]]; then
  echo "error: expected executable not found: ${BIN}" >&2
  exit 1
fi

APP_PATH="${RELEASES_DIR}/${OUTPUT_NAME}"
rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS"
mkdir -p "${APP_PATH}/Contents/Resources"

cp "${BIN}" "${APP_PATH}/Contents/MacOS/${EXECUTABLE}"
chmod 755 "${APP_PATH}/Contents/MacOS/${EXECUTABLE}"
cp "${INFO_PLIST}" "${APP_PATH}/Contents/Info.plist"

# Keep bundle metadata in sync with VERSION (e.g. VERSION_OVERRIDE from release tags).
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${APP_PATH}/Contents/Info.plist"

codesign --force --deep --sign - "${APP_PATH}"

echo "Built: ${APP_PATH}"
echo "Open: open \"${APP_PATH}\""
