#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_BIN="/Users/azaanmac/homebrew/bin/docker"
IMAGE="ghcr.io/cirruslabs/flutter:3.24.5"
VOLUME_NAME="techuboard_gradle_cache"

echo "=== Techuboard Android APK Docker High-Speed Builder ==="
echo "Repo Root: ${REPO_ROOT}"
echo "Docker Image: ${IMAGE}"

mkdir -p "${REPO_ROOT}/Techu Complete Versions/Android" "${REPO_ROOT}/dist"

# Ensure named volume exists for native Linux ext4 cache speeds
"${DOCKER_BIN}" volume create "${VOLUME_NAME}" >/dev/null 2>&1 || true

"${DOCKER_BIN}" run --rm \
  -e TECHUBOARD_ALLOW_DEBUG_SIGNING=1 \
  -v "${REPO_ROOT}:/workspace:ro" \
  -v "${REPO_ROOT}/Techu Complete Versions/Android:/out_versions" \
  -v "${REPO_ROOT}/dist:/out_dist" \
  -v "${VOLUME_NAME}:/root/.gradle" \
  "${IMAGE}" \
  bash -c "
    set -e
    echo '--> Copying source files to internal Linux container filesystem (ext4) for max speed...'
    mkdir -p /app_work
    cp -r /workspace/techuboard_android /app_work/techuboard_android
    cp -r /workspace/vendor /app_work/vendor
    
    cd /app_work/techuboard_android
    git config --global --add safe.directory '*'
    
    echo '--> Running flutter pub get...'
    flutter pub get
    
    echo '--> Building universal Release APK...'
    flutter build apk --release
    
    echo '--> Copying generated APK to output directories...'
    cp build/app/outputs/flutter-apk/app-release.apk /out_versions/Techuboard-Android-v1.0.apk
    cp build/app/outputs/flutter-apk/app-release.apk /out_dist/Techuboard-Android-v1.0.apk
    
    echo '--> Build Complete Successfully!'
    ls -lh /out_dist/Techuboard-Android-v1.0.apk
  "

echo "=== Build finished! Generated: ${REPO_ROOT}/Techu Complete Versions/Android/Techuboard-Android-v1.0.apk ==="
