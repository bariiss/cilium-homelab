CLUSTER_NAME ?= talos-home
CONTROLPLANES ?= 2
WORKERS ?= 2

# Optional: set to 1 to skip automatic dependency installation attempts
SKIP_AUTO_INSTALL ?= 0

# Core CLI dependencies required for targets
REQUIRED_BINS = talosctl kubectl cilium

OS_UNAME := $(shell uname -s 2>/dev/null)
HAVE_BREW := $(shell command -v brew >/dev/null 2>&1 && echo 1 || echo 0)

define ensure_bin
	@if ! command -v $(1) >/dev/null 2>&1; then \
		if [ "$(OS_UNAME)" = "Darwin" ] && [ "$(HAVE_BREW)" = "1" ] && [ "$(SKIP_AUTO_INSTALL)" = "0" ]; then \
			echo "[deps] Missing $(1) – attempting Homebrew install..."; \
			case "$(1)" in \
				talosctl) brew install siderolabs/tap/talosctl ;; \
				cilium) brew install cilium-cli ;; \
				kubectl) brew install kubernetes-cli ;; \
				*) echo "[deps] No install recipe for $(1)"; exit 1 ;; \
			esac; \
			if ! command -v $(1) >/dev/null 2>&1; then \
				echo "[deps] Installation of $(1) appears to have failed."; exit 1; \
			else \
				echo "[deps] Installed $(1)."; \
			fi; \
		else \
			echo "[deps] Missing required binary: $(1)"; \
			if [ "$(OS_UNAME)" = "Darwin" ] && [ "$(HAVE_BREW)" != "1" ]; then \
				echo "[deps] Homebrew not found. Install from https://brew.sh/ or install $(1) manually."; \
			fi; \
			if [ "$(SKIP_AUTO_INSTALL)" = "1" ]; then \
				echo "[deps] Auto-install skipped (SKIP_AUTO_INSTALL=1)."; \
			fi; \
			exit 1; \
		fi; \
	fi
endef

.PHONY: help deps create-cluster destroy-cluster deploy clean

help: ## Show this help message
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deps: ## Ensure required CLI tools are present (auto-install via Homebrew on macOS if possible)
ifeq ($(strip $(REQUIRED_BINS)),)
	@echo "[deps] No required binaries listed."
else
	@echo "[deps] Verifying required binaries: $(REQUIRED_BINS)";
	@for b in $(REQUIRED_BINS); do \
		echo "[deps] Checking $$b"; \
		if ! command -v $$b >/dev/null 2>&1; then \
			if [ "$(OS_UNAME)" = "Darwin" ] && [ "$(HAVE_BREW)" = "1" ] && [ "$(SKIP_AUTO_INSTALL)" = "0" ]; then \
				echo "[deps] Missing $$b – attempting Homebrew install..."; \
				case "$$b" in \
					talosctl) brew install siderolabs/tap/talosctl ;; \
					cilium) brew install cilium-cli ;; \
					kubectl) brew install kubernetes-cli ;; \
					*) echo "[deps] No install recipe for $$b"; exit 1 ;; \
				esac; \
				if ! command -v $$b >/dev/null 2>&1; then \
					echo "[deps] Installation of $$b appears to have failed."; exit 1; \
				else \
					echo "[deps] Installed $$b."; \
				fi; \
			else \
				echo "[deps] Missing required binary: $$b"; \
				if [ "$(OS_UNAME)" = "Darwin" ] && [ "$(HAVE_BREW)" != "1" ]; then \
					echo "[deps] Homebrew not found. Install from https://brew.sh/ or install $$b manually."; \
				fi; \
				if [ "$(SKIP_AUTO_INSTALL)" = "1" ]; then \
					echo "[deps] Auto-install skipped (SKIP_AUTO_INSTALL=1)."; \
				fi; \
				exit 1; \
			fi; \
		fi; \
	done
endif

# ---- Helpers (shell checks embedded in targets) ----
# "Cluster exists" if either talosctl knows it OR a talos context matches the name (or name-<n>)
define CHECK_CLUSTER_EXISTS
if talosctl cluster show --name $(CLUSTER_NAME) >/dev/null 2>&1 || \
   talosctl config contexts 2>/dev/null | awk 'NR>1 {gsub(/^\*/,"",$$1); print $$1}' | grep -qE '^$(CLUSTER_NAME)(-[0-9]+)?$$'; then \
  true; \
else \
  false; \
fi
endef

create-cluster: deps ## Create Talos cluster (override CONTROLPLANES=X WORKERS=Y) (no-op if exists)
	@echo "[create] Checking if cluster '$(CLUSTER_NAME)' already exists..."
	@$(CHECK_CLUSTER_EXISTS) && { echo "[create] Cluster $(CLUSTER_NAME) already exists; skipping."; exit 0; } || true
	@echo "[create] Pruning any stale talos contexts matching $(CLUSTER_NAME)(-N)..."
	@contexts=$$(talosctl config contexts 2>/dev/null | awk 'NR>1 {gsub(/^\*/,"",$$1); print $$1}' | grep -E '^$(CLUSTER_NAME)(-[0-9]+)?$$' || true); \
	if [ -n "$$contexts" ]; then \
	  echo "[create] Removing talos contexts: $$contexts"; \
	  talosctl config remove $$contexts 2>/dev/null || true; \
	else \
	  echo "[create] No matching contexts"; \
	fi
	talosctl cluster create --name $(CLUSTER_NAME) \
		--controlplanes $(CONTROLPLANES) \
		--workers $(WORKERS) \
		--config-patch @talos/patch.yaml \
		--skip-k8s-node-readiness-check

destroy-cluster: ## Destroy Talos cluster (no-op if absent)
	@echo "[destroy] Checking if cluster '$(CLUSTER_NAME)' exists..."
	@$(CHECK_CLUSTER_EXISTS) || { echo "[destroy] Cluster $(CLUSTER_NAME) not found; nothing to do."; exit 0; }
	talosctl cluster destroy --name $(CLUSTER_NAME) || true
	@echo "[destroy] Cluster $(CLUSTER_NAME) destroyed."

deploy: deps ## Generate manifests & deploy core stack (no-op if already deployed)
	@echo "[deploy] Checking for existing Cilium installation..."
	@if kubectl -n kube-system get ds cilium >/dev/null 2>&1 && \
	     kubectl -n kube-system get deploy cilium-operator >/dev/null 2>&1; then \
	  echo "[deploy] Core stack (Cilium) already applied; skipping."; \
	  exit 0; \
	fi
	@echo "[deploy] Rendering Cilium manifests (dry-run) -> deploy/00-core/cilium-manifests.yaml"
	@mkdir -p deploy/00-core
	cilium install --values cilium/cilium-values.yaml --dry-run > deploy/00-core/cilium-manifests.yaml
	kubectl apply -k deploy/00-core
	kubectl -n kube-system rollout status ds/cilium --timeout=5m
	kubectl -n kube-system rollout status deploy/cilium-operator --timeout=5m
	@echo "[deploy] Generated Cilium manifests applied."

clean: destroy-cluster ## Clean up everything