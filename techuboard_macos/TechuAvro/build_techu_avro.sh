#!/usr/bin/env bash
# build_techu_avro.sh — Builds TechuAvro.app, an InputMethodKit-based Bangla IME.
# Usage: ./techuboard_macos/TechuAvro/build_techu_avro.sh [--install]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TECHU_AVRO_DIR="${REPO_ROOT}/techuboard_macos/TechuAvro"
APP_NAME="TechuAvro"
APP_BUNDLE="${APP_NAME}.app"
BUNDLE_ID="com.techuboard.techu-avro"
ARCH="${MACOS_ARCH:-arm64}"
INSTALL="${1:-}"

[ "$(uname -s)" = Darwin ] || { echo "ERROR: Must run on macOS"; exit 1; }
command -v swiftc &>/dev/null || { echo "ERROR: swiftc not found"; exit 1; }

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/techu-avro-build.XXXXXX")"
trap 'rm -rf "${BUILD_DIR}"' EXIT

STAGED_APP="${BUILD_DIR}/${APP_BUNDLE}"
mkdir -p "${STAGED_APP}/Contents/MacOS" "${STAGED_APP}/Contents/Resources"

# Collect sources
SWIFT_SOURCES=()
while IFS= read -r -d '' f; do
  SWIFT_SOURCES+=("${f}")
done < <(find "${TECHU_AVRO_DIR}/Sources" -name '*.swift' -print0)

[ "${#SWIFT_SOURCES[@]}" -gt 0 ] || { echo "ERROR: No Swift sources found"; exit 1; }

echo "Compiling ${APP_NAME} for ${ARCH}..."
swiftc "${SWIFT_SOURCES[@]}" \
  -whole-module-optimization \
  -swift-version 5 \
  -target "${ARCH}-apple-macos13.0" \
  -emit-object \
  -emit-module \
  -module-name "${APP_NAME}" \
  -emit-module-path "${BUILD_DIR}/${APP_NAME}.swiftmodule" \
  -o "${BUILD_DIR}/${APP_NAME}.o"

echo "Linking..."
swiftc "${BUILD_DIR}/${APP_NAME}.o" \
  -target "${ARCH}-apple-macos13.0" \
  -o "${STAGED_APP}/Contents/MacOS/${APP_NAME}" \
  -framework AppKit \
  -framework InputMethodKit \
  -framework Carbon

# Copy plist
cp "${TECHU_AVRO_DIR}/Resources/Info.plist" "${STAGED_APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${APP_NAME}" "${STAGED_APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "${STAGED_APP}/Contents/Info.plist"
plutil -lint "${STAGED_APP}/Contents/Info.plist"

# Ad-hoc sign
codesign --force --sign - --identifier "${BUNDLE_ID}" --timestamp=none "${STAGED_APP}"
codesign --verify --deep --strict "${STAGED_APP}"

# Output
OUTPUT="${TECHU_AVRO_DIR}/${APP_BUNDLE}"
rm -rf "${OUTPUT}"
mv "${STAGED_APP}" "${OUTPUT}"
echo "Built: ${OUTPUT}"

# Install?
if [ "${INSTALL}" = "--install" ]; then
  DEST=~/Library/Input\ Methods/TechuAvro.app
  rm -rf "${DEST}"
  cp -R "${OUTPUT}" "${DEST}"
  echo "Installed to: ${DEST}"
  # Re-register with TIS
  /System/Library/CoreServices/pbs -flush 2>/dev/null || true
fi
