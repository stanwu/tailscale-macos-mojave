#!/bin/bash
set -euo pipefail

# ============================================================
# Run Tailscale v1.76.3 on macOS 10.14 Mojave
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TAILSCALED="$SCRIPT_DIR/tailscaled"
TAILSCALE="$SCRIPT_DIR/tailscale"
STATE_DIR="/var/lib/tailscale"
SOCKET="/var/run/tailscaled.sock"

# --- Check binaries exist ---
if [ ! -x "$TAILSCALED" ] || [ ! -x "$TAILSCALE" ]; then
    echo "[ERROR] tailscale or tailscaled not found in $SCRIPT_DIR"
    echo "Make sure both binaries are in the same directory as this script."
    exit 1
fi

# --- Check root ---
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This script must be run as root."
    echo "Usage: sudo $0"
    exit 1
fi

# --- Create state directory ---
mkdir -p "$STATE_DIR"

# --- Stop existing tailscaled if running ---
if pgrep -x tailscaled &>/dev/null; then
    echo "[INFO] Stopping existing tailscaled..."
    killall tailscaled 2>/dev/null || true
    sleep 2
fi

# --- Start daemon ---
echo "[INFO] Starting tailscaled..."
"$TAILSCALED" --state="$STATE_DIR/tailscaled.state" --socket="$SOCKET" &
DAEMON_PID=$!
sleep 2

if kill -0 "$DAEMON_PID" 2>/dev/null; then
    echo "[OK] tailscaled running (PID: $DAEMON_PID)"
else
    echo "[ERROR] tailscaled failed to start."
    exit 1
fi

# --- Connect ---
echo "[INFO] Connecting to Tailscale network..."
"$TAILSCALE" --socket="$SOCKET" up

echo ""
echo "[OK] Tailscale is running."
echo ""
"$TAILSCALE" --socket="$SOCKET" status
