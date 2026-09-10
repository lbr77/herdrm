#!/bin/sh
# Builds the herdr-tailcat-bridge helper as a universal (arm64 + x86_64) macOS
# binary and installs it to ~/.local/bin, where HerdrKit's TailcatBridgeManager
# finds it via the login-shell PATH (after the app-bundle resource lookup).
#
# Requires: Go. The tailcat dependency is a published module, so the build
# fetches it from the Go module proxy (no local checkout needed). Run from
# anywhere:
#
#   sh Tools/herdr-tailcat-bridge/build.sh
set -eu

cd "$(dirname "$0")"

BIN=herdr-tailcat-bridge
INSTALL_DIR="${HOME}/.local/bin"

echo "building arm64…"
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags="-s -w" -o ".build/${BIN}-arm64" .

echo "building x86_64…"
CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o ".build/${BIN}-amd64" .

echo "lipo → universal…"
lipo -create -output ".build/${BIN}" ".build/${BIN}-arm64" ".build/${BIN}-amd64"

mkdir -p "${INSTALL_DIR}"
install -m 0755 ".build/${BIN}" "${INSTALL_DIR}/${BIN}"

echo "installed ${INSTALL_DIR}/${BIN}"
lipo -info "${INSTALL_DIR}/${BIN}"
