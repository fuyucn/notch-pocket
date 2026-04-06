#!/usr/bin/env bash
# Build a distributable .app from the Swift Package (DropZone/) Release binaries.
# Universal binary (arm64 + x86_64) via lipo — runs on Apple Silicon and Intel Macs.
# Output: releases/Notch Pocket-<version>.app
# Requires full Xcode toolchain (not CLT-only for some setups).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${ROOT}/DropZone"
RELEASES_DIR="${RELEASES_DIR:-${ROOT}/releases}"

EXECUTABLE="DropZone"
INFO_PLIST="${PKG_DIR}/Info.plist"
APP_BASE_NAME="${APP_BASE_NAME:-Notch Pocket}"

TRIPLE_ARM64="${TRIPLE_ARM64:-arm64-apple-macosx14.0}"
TRIPLE_X86="${TRIPLE_X86:-x86_64-apple-macosx14.0}"

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
  OUTPUT_NAME="${APP_NAME}"
fi

mkdir -p "${RELEASES_DIR}"
cd "$PKG_DIR"

swift build -c release --triple "${TRIPLE_ARM64}"
swift build -c release --triple "${TRIPLE_X86}"
ARM_DIR="$(swift build -c release --triple "${TRIPLE_ARM64}" --show-bin-path)"
X86_DIR="$(swift build -c release --triple "${TRIPLE_X86}" --show-bin-path)"
BIN_ARM="${ARM_DIR}/${EXECUTABLE}"
BIN_X86="${X86_DIR}/${EXECUTABLE}"
if [[ ! -f "$BIN_ARM" || ! -f "$BIN_X86" ]]; then
  echo "error: missing arch slice(s): ${BIN_ARM} ${BIN_X86}" >&2
  exit 1
fi

APP_PATH="${RELEASES_DIR}/${OUTPUT_NAME}"
rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources"

lipo -create -output "${APP_PATH}/Contents/MacOS/${EXECUTABLE}" "${BIN_ARM}" "${BIN_X86}"
chmod 755 "${APP_PATH}/Contents/MacOS/${EXECUTABLE}"
cp "${INFO_PLIST}" "${APP_PATH}/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "${APP_PATH}/Contents/Info.plist"

codesign --force --deep --sign - "${APP_PATH}"

echo "Built: ${APP_PATH}"
echo "Open: open \"${APP_PATH}\""
