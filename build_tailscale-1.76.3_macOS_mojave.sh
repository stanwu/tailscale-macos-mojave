#!/bin/bash
set -euo pipefail

# ============================================================
# Build Tailscale v1.76.3 static binary for macOS 10.14 Mojave
# Target: darwin/amd64
# Run on: Linux (cross-compile)
# ============================================================

VERSION="v1.76.3"
# GOVERSION_MIN="1.23"  # reserved for future version check
OUTPUT_DIR="$HOME/tailscale-build/darwin_amd64"
SRC_DIR="$HOME/tailscale-build/src"

echo "=== Tailscale ${VERSION} cross-compile for macOS (darwin/amd64) ==="
echo ""

# --- 1. Check Go is installed ---
if ! command -v go &>/dev/null; then
    echo "[ERROR] Go is not installed."
    echo "Install with: sudo apt install golang-go  or  brew install go"
    exit 1
fi

GO_VER=$(go version | grep -oP 'go\K[0-9]+\.[0-9]+')
export GO_VER
echo "[OK] Go version: $(go version)"

# --- 2. Create build directories ---
mkdir -p "$OUTPUT_DIR" "$SRC_DIR"
echo "[OK] Build directory: $OUTPUT_DIR"

# --- 3. Clone source code ---
if [ -d "$SRC_DIR/tailscale" ]; then
    echo "[INFO] Source directory exists, cleaning..."
    rm -rf "$SRC_DIR/tailscale"
fi

echo "[INFO] Cloning Tailscale ${VERSION} source code..."
git clone --depth 1 --branch "${VERSION}" https://github.com/tailscale/tailscale.git "$SRC_DIR/tailscale"
echo "[OK] Source code cloned."

# --- 4. Build ---
cd "$SRC_DIR/tailscale"

echo ""

# macOS 10.14 Mojave compatibility:
# - MACOSX_DEPLOYMENT_TARGET=10.14 forces Mach-O minimum version to 10.14
#   preventing the linker from referencing APIs newer than Mojave
#   (e.g. _SecTrustCopyCertificateChain requires macOS 12+)
# - osusergo,netgo tags ensure pure Go implementations for user/net packages
export MACOSX_DEPLOYMENT_TARGET=10.14

OVERLAY="$HOME/tailscale-build/mojave_amd64/overlay.json"
LDFLAGS="-s -w -X tailscale.com/version.longStamp=${VERSION} -X tailscale.com/version.shortStamp=${VERSION}"

# Clear Go build cache to ensure overlay takes effect
go clean -cache

echo "[INFO] Building tailscaled (daemon)..."
CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build \
    -overlay "$OVERLAY" \
    -tags osusergo,netgo \
    -o "$OUTPUT_DIR/tailscaled" \
    -ldflags "${LDFLAGS}" \
    ./cmd/tailscaled

echo "[INFO] Building tailscale (CLI)..."
CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build \
    -overlay "$OVERLAY" \
    -tags osusergo,netgo \
    -o "$OUTPUT_DIR/tailscale" \
    -ldflags "${LDFLAGS}" \
    ./cmd/tailscale

# --- 5. Verify ---
echo ""
echo "=== Build complete ==="
echo ""
ls -lh "$OUTPUT_DIR"/tailscale*
echo ""
file "$OUTPUT_DIR"/tailscale*
echo ""
echo "Output: $OUTPUT_DIR/"
echo ""
echo "=== Next steps ==="
echo "1. Copy to Mojave machine:"
echo "   scp $OUTPUT_DIR/tailscale $OUTPUT_DIR/tailscaled user@mojave-host:~/"
echo ""
echo "2. On Mojave, start daemon:"
echo "   sudo ./tailscaled &"
echo ""
echo "3. Login:"
echo "   ./tailscale up"
echo ""
echo "4. (Optional) Install as system daemon:"
echo "   sudo ./tailscaled install-system-daemon"
