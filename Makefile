VERSION     := v1.76.3
REPO        := https://github.com/tailscale/tailscale.git
SRC_DIR     := src/tailscale
OUTPUT_DIR  := mojave_amd64
OVERLAY     := $(OUTPUT_DIR)/overlay.json

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

# Deploy target (override with: make deploy DEPLOY_HOST=user@host)
DEPLOY_HOST ?= user@mojave-host
DEPLOY_PATH ?= ~/

.PHONY: all build clone clean clean-cache verify deploy setup help

all: build

# ---- Build ----

build: $(BINARIES)
	@echo ""
	@echo "=== Build complete ==="
	@ls -lh $(BINARIES)
	@file $(BINARIES)

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

verify: $(BINARIES)
	@echo "=== Verify: SecTrustCopyCertificateChain should NOT appear ==="
	@! strings $(TAILSCALE) | grep -q SecTrustCopyCertificateChain && \
		echo "[OK] SecTrustCopyCertificateChain removed" || \
		(echo "[FAIL] SecTrustCopyCertificateChain still present" && exit 1)
	@strings $(TAILSCALE) | grep -q SecTrustGetCertificateAtIndex && \
		echo "[OK] SecTrustGetCertificateAtIndex present" || \
		(echo "[FAIL] SecTrustGetCertificateAtIndex missing" && exit 1)

# ---- Deploy ----

deploy: $(BINARIES)
	@echo "[INFO] Deploying to $(DEPLOY_HOST):$(DEPLOY_PATH)"
	scp $(BINARIES) $(OUTPUT_DIR)/run_tailscale.sh $(DEPLOY_HOST):$(DEPLOY_PATH)
	@echo "[OK] Deployed. Run on Mojave: sudo ./run_tailscale.sh"

# ---- Clean ----

clean:
	rm -f $(BINARIES)
	@echo "[OK] Binaries removed"

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
	@echo "Targets:"
	@echo "  make              Build tailscale + tailscaled"
	@echo "  make clone        Clone Tailscale source only"
	@echo "  make verify       Check binary symbols are patched correctly"
	@echo "  make deploy       scp binaries to Mojave host"
	@echo "  make clean        Remove binaries"
	@echo "  make clean-cache  Remove binaries + Go build cache"
	@echo "  make clean-all    Remove binaries + cloned source"
	@echo "  make setup        Create venv + install pre-commit"
	@echo ""
	@echo "Options:"
	@echo "  DEPLOY_HOST=user@host  Deploy target (default: user@mojave-host)"
	@echo "  DEPLOY_PATH=~/dir      Remote path   (default: ~/)"
