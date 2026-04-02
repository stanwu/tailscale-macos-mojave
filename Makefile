VERSION     := v1.76.3
REPO        := https://github.com/tailscale/tailscale.git
SRC_DIR     := src/tailscale
OUTPUT_DIR  := mojave_amd64

GOOS        := darwin
GOARCH      := amd64
CGO_ENABLED := 0
MACOSX_DEPLOYMENT_TARGET := 10.14

BUILDTAGS   := osusergo,netgo
LDFLAGS     := -s -w -X tailscale.com/version.longStamp=$(VERSION) -X tailscale.com/version.shortStamp=$(VERSION)

GO_ENV      := CGO_ENABLED=$(CGO_ENABLED) GOOS=$(GOOS) GOARCH=$(GOARCH) MACOSX_DEPLOYMENT_TARGET=$(MACOSX_DEPLOYMENT_TARGET)

TAILSCALE   := $(OUTPUT_DIR)/tailscale
TAILSCALED  := $(OUTPUT_DIR)/tailscaled
BINARIES    := $(TAILSCALE) $(TAILSCALED)
SPEC        := mach-o-header-symbols.json
OVERLAY     := $(OUTPUT_DIR)/overlay.json

# --- Go version detection ---
# Auto-detect Go major.minor version and select matching overlay.
# Override with: make GO_OVERLAY=go123
#
# Go 1.26+: package name is "macos"  (lowercase) -> overlay/go126
# Go 1.23-1.25: package name is "macOS" (capital S) -> overlay/go123
GO_VER_RAW  := $(shell go version | grep -oP 'go\K[0-9]+\.[0-9]+')
GO_VER_MAJ  := $(word 1,$(subst ., ,$(GO_VER_RAW)))
GO_VER_MIN  := $(word 2,$(subst ., ,$(GO_VER_RAW)))
GO_OVERLAY  ?= $(shell [ "$(GO_VER_MIN)" -ge 26 ] 2>/dev/null && echo go126 || echo go123)
OVERLAY_DIR := $(CURDIR)/overlay/$(GO_OVERLAY)
GOROOT_SRC  := $(shell go env GOROOT)/src

# Package subdir name differs between Go versions
ifeq ($(GO_OVERLAY),go126)
  MACOS_PKG := macos
else
  MACOS_PKG := macOS
endif

# Deploy target (override with: make deploy DEPLOY_HOST=user@host)
DEPLOY_HOST ?= user@mojave-host
DEPLOY_PATH ?= ~/

.PHONY: all build clone clean clean-cache clean-all verify deploy setup check-go help

all: build

# ---- Go version check ----

check-go:
	@echo "[INFO] Go version: $(GO_VER_RAW) -> overlay: $(GO_OVERLAY) (package: $(MACOS_PKG))"
	@test -d "$(OVERLAY_DIR)" || \
		(echo "[ERROR] Overlay directory not found: $(OVERLAY_DIR)" && \
		 echo "        Available: $$(ls -d overlay/go* 2>/dev/null)" && \
		 echo "        Override with: make GO_OVERLAY=go123" && exit 1)

# ---- Build ----

build: check-go $(BINARIES)
	@echo ""
	@echo "=== Build complete ($(GO_OVERLAY)) ==="
	@ls -lh $(BINARIES)
	@file $(BINARIES)

$(OVERLAY): check-go $(wildcard $(OVERLAY_DIR)/crypto/x509/internal/$(MACOS_PKG)/*) $(wildcard $(OVERLAY_DIR)/crypto/x509/*)
	@mkdir -p $(OUTPUT_DIR)
	@printf '{\n  "Replace": {\n    "%s/crypto/x509/internal/%s/security.go": "%s/crypto/x509/internal/%s/security.go",\n    "%s/crypto/x509/internal/%s/security.s": "%s/crypto/x509/internal/%s/security.s",\n    "%s/crypto/x509/root_darwin.go": "%s/crypto/x509/root_darwin.go"\n  }\n}\n' \
		"$(GOROOT_SRC)" "$(MACOS_PKG)" "$(OVERLAY_DIR)" "$(MACOS_PKG)" \
		"$(GOROOT_SRC)" "$(MACOS_PKG)" "$(OVERLAY_DIR)" "$(MACOS_PKG)" \
		"$(GOROOT_SRC)" "$(OVERLAY_DIR)" > $@
	@echo "[OK] Generated overlay.json ($(GO_OVERLAY), package: $(MACOS_PKG))"

$(TAILSCALED): $(SRC_DIR)/go.mod $(OVERLAY)
	@echo "[INFO] Building tailscaled (daemon)..."
	cd $(SRC_DIR) && $(GO_ENV) go build \
		-overlay ../../$(OVERLAY) \
		-tags $(BUILDTAGS) \
		-ldflags "$(LDFLAGS)" \
		-o ../../$@ \
		./cmd/tailscaled

$(TAILSCALE): $(SRC_DIR)/go.mod $(OVERLAY)
	@echo "[INFO] Building tailscale (CLI)..."
	cd $(SRC_DIR) && $(GO_ENV) go build \
		-overlay ../../$(OVERLAY) \
		-tags $(BUILDTAGS) \
		-ldflags "$(LDFLAGS)" \
		-o ../../$@ \
		./cmd/tailscale

# ---- Clone source ----

clone: $(SRC_DIR)/go.mod

$(SRC_DIR)/go.mod:
	@echo "[INFO] Cloning Tailscale $(VERSION)..."
	git clone --depth 1 --branch $(VERSION) $(REPO) $(SRC_DIR)

# ---- Verify ----

verify: $(BINARIES) $(SPEC)
	@python3 scripts/verify_macho.py $(SPEC) $(TAILSCALE) $(TAILSCALED)

# ---- Deploy ----

deploy: $(BINARIES)
	@echo "[INFO] Deploying to $(DEPLOY_HOST):$(DEPLOY_PATH)"
	scp $(BINARIES) run_tailscale.sh $(DEPLOY_HOST):$(DEPLOY_PATH)
	@echo "[OK] Deployed. Run on Mojave: sudo ./run_tailscale.sh"

# ---- Clean ----

clean:
	rm -f $(BINARIES) $(OVERLAY)
	@echo "[OK] Binaries and overlay.json removed"

clean-cache: clean
	go clean -cache
	@echo "[OK] Go build cache cleared"

clean-all: clean
	rm -rf $(SRC_DIR)
	@echo "[OK] Source and binaries removed"

# ---- Dev setup ----

setup:
	python3 -m venv venv
	. venv/bin/activate && pip install pre-commit && pre-commit install
	@echo "[OK] venv + pre-commit ready"

# ---- Help ----

help:
	@echo "Tailscale $(VERSION) macOS Mojave Cross-Compile"
	@echo ""
	@echo "  Detected Go: $(GO_VER_RAW) -> overlay: $(GO_OVERLAY)"
	@echo ""
	@echo "Targets:"
	@echo "  make              Build tailscale + tailscaled"
	@echo "  make clone        Clone Tailscale source only"
	@echo "  make check-go     Show detected Go version and overlay"
	@echo "  make verify       Verify Mach-O header + symbols against spec"
	@echo "  make deploy       scp binaries to Mojave host"
	@echo "  make clean        Remove binaries + generated overlay.json"
	@echo "  make clean-cache  Remove binaries + Go build cache"
	@echo "  make clean-all    Remove binaries + cloned source"
	@echo "  make setup        Create venv + install pre-commit"
	@echo ""
	@echo "Options:"
	@echo "  GO_OVERLAY=go123       Force Go 1.23-1.25 overlay (package macOS)"
	@echo "  GO_OVERLAY=go126       Force Go 1.26+ overlay    (package macos)"
	@echo "  DEPLOY_HOST=user@host  Deploy target (default: user@mojave-host)"
	@echo "  DEPLOY_PATH=~/dir      Remote path   (default: ~/)"
