#!/usr/bin/env bash
# Download the official sherpa-onnx macOS static libraries and repackage them
# as a single xcframework for this project's SwiftPM layout.
#
# Usage: bash scripts/setup-sherpa-onnx.sh [--force]

set -euo pipefail

SHERPA_VERSION="1.12.35"
ARCHIVE_NAME="sherpa-onnx-v${SHERPA_VERSION}-osx-universal2-static-lib.tar.bz2"
DOWNLOAD_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${SHERPA_VERSION}/${ARCHIVE_NAME}"

# For the C API header (flat layout)
HEADER_ARCHIVE_NAME="sherpa-onnx-v${SHERPA_VERSION}-macos-xcframework-static.tar.bz2"
HEADER_DOWNLOAD_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${SHERPA_VERSION}/${HEADER_ARCHIVE_NAME}"

DEST_DIR="Frameworks/sherpa_onnx.xcframework"
LIB_DIR="${DEST_DIR}/macos-arm64_x86_64"
HEADER_DIR="${LIB_DIR}/Headers"

FORCE=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE=true
fi

# Skip if already set up (unless --force)
if [[ -f "${LIB_DIR}/libsherpa_onnx.a" && "${FORCE}" == "false" ]]; then
    echo "sherpa-onnx xcframework already present. Use --force to re-download."
    exit 0
fi

TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "${TMPDIR_WORK}"' EXIT

echo "Downloading sherpa-onnx v${SHERPA_VERSION} static libraries..."
curl -fSL --progress-bar "${DOWNLOAD_URL}" -o "${TMPDIR_WORK}/${ARCHIVE_NAME}"

echo "Downloading sherpa-onnx v${SHERPA_VERSION} headers..."
curl -fSL --progress-bar "${HEADER_DOWNLOAD_URL}" -o "${TMPDIR_WORK}/${HEADER_ARCHIVE_NAME}"

echo "Extracting..."
tar -xjf "${TMPDIR_WORK}/${ARCHIVE_NAME}" -C "${TMPDIR_WORK}"
tar -xjf "${TMPDIR_WORK}/${HEADER_ARCHIVE_NAME}" -C "${TMPDIR_WORK}"

LIB_SRC="${TMPDIR_WORK}/sherpa-onnx-v${SHERPA_VERSION}-osx-universal2-static-lib/lib"
HEADER_SRC="${TMPDIR_WORK}/sherpa-onnx-v${SHERPA_VERSION}-macos-xcframework-static/sherpa-onnx.xcframework/macos-arm64_x86_64/Headers"

if [[ ! -d "${LIB_SRC}" ]]; then
    echo "Error: lib directory not found: ${LIB_SRC}" >&2
    exit 1
fi

echo "Merging static libraries into single archive..."
rm -rf "${DEST_DIR}"
mkdir -p "${HEADER_DIR}"

# Merge all component static libraries into one combined archive.
# Exclude portaudio (not needed for this app).
LIBS_TO_MERGE=(
    "${LIB_SRC}/libsherpa-onnx-c-api.a"
    "${LIB_SRC}/libsherpa-onnx-core.a"
    "${LIB_SRC}/libonnxruntime.a"
    "${LIB_SRC}/libkaldi-native-fbank-core.a"
    "${LIB_SRC}/libkissfft-float.a"
    "${LIB_SRC}/libkaldi-decoder-core.a"
    "${LIB_SRC}/libsherpa-onnx-kaldifst-core.a"
    "${LIB_SRC}/libsherpa-onnx-fst.a"
    "${LIB_SRC}/libsherpa-onnx-fstfar.a"
    "${LIB_SRC}/libssentencepiece_core.a"
    "${LIB_SRC}/libucd.a"
    "${LIB_SRC}/libespeak-ng.a"
    "${LIB_SRC}/libpiper_phonemize.a"
)

libtool -static -o "${LIB_DIR}/libsherpa_onnx.a" "${LIBS_TO_MERGE[@]}" 2>/dev/null

# Copy the C API header
cp "${HEADER_SRC}/sherpa-onnx/c-api/c-api.h" "${HEADER_DIR}/c-api.h"

# Create umbrella header
cat > "${HEADER_DIR}/sherpa_onnx.h" << 'EOF'
#ifndef SHERPA_ONNX_H
#define SHERPA_ONNX_H

#include "c-api.h"

#endif  // SHERPA_ONNX_H
EOF

# Create modulemap
cat > "${HEADER_DIR}/module.modulemap" << 'EOF'
module sherpa_onnx {
    umbrella header "sherpa_onnx.h"
    export *
    link "c++"
}
EOF

# Create xcframework Info.plist
cat > "${DEST_DIR}/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
		<dict>
			<key>BinaryPath</key>
			<string>libsherpa_onnx.a</string>
			<key>HeadersPath</key>
			<string>Headers</string>
			<key>LibraryIdentifier</key>
			<string>macos-arm64_x86_64</string>
			<key>LibraryPath</key>
			<string>libsherpa_onnx.a</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
				<string>x86_64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>macos</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key>
	<string>XFWK</string>
	<key>XCFrameworkFormatVersion</key>
	<string>1.0</string>
</dict>
</plist>
EOF

FINAL_SIZE=$(du -h "${LIB_DIR}/libsherpa_onnx.a" | cut -f1)
echo "Done. sherpa-onnx v${SHERPA_VERSION} xcframework installed at ${DEST_DIR} (${FINAL_SIZE})"
