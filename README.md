# Tailscale v1.76.3 — macOS 10.14 Mojave Cross-Compile

Cross-compile Tailscale static binaries (`tailscale` + `tailscaled`) for **macOS 10.14 Mojave (darwin/amd64)** on a Linux host.

## Why

Tailscale officially dropped macOS 10.14 support. This project builds a compatible binary by using Go's `-overlay` mechanism to patch the standard library, replacing macOS 12+ APIs with Mojave-compatible equivalents.

## The Problem

Go 1.26's `crypto/x509` standard library references `SecTrustCopyCertificateChain`, a Security framework API available only on **macOS 12+**. Even with `CGO_ENABLED=0`, Go on darwin dynamically loads Security framework symbols at runtime via `//go:cgo_import_dynamic`, causing an immediate crash on Mojave:

```
dyld: Symbol not found: _SecTrustCopyCertificateChain
  Referenced from: ./tailscale (which was built for Mac OS X 12.0)
Abort trap: 6
```

### What Doesn't Work

| Approach | Why It Fails |
|---|---|
| `CGO_ENABLED=0` | Go on darwin still loads system frameworks via `//go:cgo_import_dynamic` + assembly trampoline — not truly zero system dependency |
| `MACOSX_DEPLOYMENT_TARGET=10.14` | Only changes Mach-O header minimum version tag, does NOT change which APIs the Go stdlib references |

## The Solution: Go `-overlay` Patch

Use Go's `-overlay` build flag to replace 3 standard library files at compile time, swapping the macOS 12+ API for two older Mojave-compatible APIs:

| New API (macOS 12+) | Old API Replacement (macOS 10.7+) |
|---|---|
| `SecTrustCopyCertificateChain(trust)` — returns entire cert chain as CFArray | `SecTrustGetCertificateCount(trust)` — get chain length |
| | `SecTrustGetCertificateAtIndex(trust, i)` — get cert one by one |

### Patched Files

| File | Change |
|---|---|
| `crypto/x509/internal/macos/security.go` | Remove `SecTrustCopyCertificateChain`, add `SecTrustGetCertificateCount` + `SecTrustGetCertificateAtIndex` with `cgo_import_dynamic` |
| `crypto/x509/internal/macos/security.s` | Remove old assembly trampoline, add two new trampolines |
| `crypto/x509/root_darwin.go` | Change from single CFArray fetch to count + index loop |

### Key Code Change in `root_darwin.go`

Before (macOS 12+):

```go
chainRef, err := macos.SecTrustCopyCertificateChain(trustObj)
defer macos.CFRelease(chainRef)
for i := 0; i < macos.CFArrayGetCount(chainRef); i++ {
    certRef := macos.CFArrayGetValueAtIndex(chainRef, i)
    // ...
}
```

After (macOS 10.7+ compatible):

```go
certCount := macos.SecTrustGetCertificateCount(trustObj)
for i := 0; i < certCount; i++ {
    certRef := macos.SecTrustGetCertificateAtIndex(trustObj, i)
    // ...
}
```

> Note: `SecTrustGetCertificateAtIndex` uses "Get" semantics (borrowed ref) — no `CFRelease` needed. `SecTrustCopyCertificateChain` uses "Copy" semantics (caller owns) — requires `CFRelease`. This follows Apple's Core Foundation memory management rules.

## Prerequisites

- Go >= 1.23
- git
- Linux build host (cross-compile)

## Build

```bash
./build_tailscale-1.76.3_macOS_mojave.sh
```

Output binaries are written to `mojave_amd64/`.

### Manual Build (with overlay)

```bash
cd src/tailscale
go clean -cache

export MACOSX_DEPLOYMENT_TARGET=10.14
export CGO_ENABLED=0
export GOOS=darwin
export GOARCH=amd64

OVERLAY="../../mojave_amd64/overlay.json"
LDFLAGS="-s -w -X tailscale.com/version.longStamp=v1.76.3 -X tailscale.com/version.shortStamp=v1.76.3"

go build -overlay "$OVERLAY" -tags osusergo,netgo \
    -o ../../mojave_amd64/tailscaled -ldflags "$LDFLAGS" ./cmd/tailscaled

go build -overlay "$OVERLAY" -tags osusergo,netgo \
    -o ../../mojave_amd64/tailscale -ldflags "$LDFLAGS" ./cmd/tailscale
```

### Verify

```bash
# Confirm problematic symbol is gone
strings tailscale | grep SecTrustCopyCertificateChain    # (no output = good)

# Confirm new API is present
strings tailscale | grep SecTrustGetCertificateAtIndex   # (should show)
```

## Deploy to Mojave

```bash
scp mojave_amd64/{tailscale,tailscaled,run_tailscale.sh} user@mojave-host:~/
```

On the Mojave machine:

```bash
sudo ./run_tailscale.sh
```

### Socket Path Issue

After deployment, `tailscale status` may hang because the CLI defaults to the macOS GUI socket path. The self-compiled `tailscaled` daemon uses `/var/run/tailscaled.sock`. Fix with an alias:

```bash
# Add to ~/.bashrc
alias tailscale="/path/to/tailscale --socket=/var/run/tailscaled.sock"
```

## Project Structure

```
build_tailscale-1.76.3_macOS_mojave.sh  # Main build script
Makefile                                # Build/deploy/verify targets
overlay/                                # Go stdlib patches (tracked in git)
  crypto/x509/internal/macos/
    security.go                         # Patched: old API replacements
    security.s                          # Patched: new assembly trampolines
  crypto/x509/
    root_darwin.go                      # Patched: count+index loop
run_tailscale.sh                        # Startup helper for Mojave
.github/workflows/build.yml            # CI: build + release on tag
mojave_amd64/                           # Build output (git-ignored)
src/                                    # Cloned Tailscale source (git-ignored)
```

> Note: `overlay.json` is generated at build time with correct absolute paths. It is not tracked in git to avoid leaking local filesystem paths.

## Key Lessons

1. **`CGO_ENABLED=0` on darwin ≠ zero system dependency** — Go loads Security.framework at runtime via `//go:cgo_import_dynamic` + assembly trampoline
2. **`MACOSX_DEPLOYMENT_TARGET` cannot fix symbol issues** — it only changes the Mach-O header, not which APIs the code references
3. **Go `-overlay` is the correct way to patch stdlib** — no need to fork Go or modify `$GOROOT`
4. **Apple Core Foundation memory rules matter** — `Copy`/`Create` = caller must `CFRelease`; `Get` = borrowed, no release needed

## Development

Pre-commit hooks are configured. To set up:

```bash
python3 -m venv venv
source venv/bin/activate
pip install pre-commit
pre-commit install
```
