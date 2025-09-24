CLUSTER_NAME ?= talos-home
CONTROLPLANES ?= 1
WORKERS ?= 1

# Specific resource allocation for control plane nodes
CONTROLPLANE_CPUS ?= 2
CONTROLPLANE_MEMORY ?= 2048

# Specific resource allocation for worker nodes  
WORKER_CPUS ?= 2
WORKER_MEMORY ?= 2048

# Optional: set to 1 to skip automatic dependency installation attempts
SKIP_AUTO_INSTALL ?= 0

# Core CLI dependencies required for targets
REQUIRED_BINS = talosctl kubectl cilium

OS_UNAME := $(shell uname -s 2>/dev/null)
HAVE_BREW := $(shell command -v brew >/dev/null 2>&1 && echo 1 || echo 0)



.PHONY: help deps create-cluster destroy-cluster deploy clean

help: ## Show this help message
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

deps: ## Ensure required CLI tools are present (auto-install on macOS/Linux)
ifeq ($(strip $(REQUIRED_BINS)),)
	@echo "[deps] No required binaries listed."
else
	@echo "[deps] Verifying required binaries: $(REQUIRED_BINS)";
	@for b in $(REQUIRED_BINS); do \
		echo "[deps] Checking $$b"; \
		if command -v $$b >/dev/null 2>&1; then \
			echo "[deps] ✓ $$b is already installed"; \
		elif [ "$(SKIP_AUTO_INSTALL)" = "0" ]; then \
			echo "[deps] Missing $$b – attempting installation..."; \
			if [ "$(OS_UNAME)" = "Darwin" ] && [ "$(HAVE_BREW)" = "1" ]; then \
				case "$$b" in \
					talosctl) brew install siderolabs/tap/talosctl ;; \
					cilium) brew install cilium-cli ;; \
					kubectl) brew install kubernetes-cli ;; \
					*) echo "[deps] No Homebrew recipe for $$b"; exit 1 ;; \
				esac; \
			elif [ "$(OS_UNAME)" = "Linux" ]; then \
				case "$$b" in \
					talosctl) \
						echo "[deps] Installing talosctl for Linux..."; \
						curl -sL https://talos.dev/install | sh; \
						sudo mv talosctl /usr/local/bin/; \
						;; \
					cilium) \
						echo "[deps] Installing cilium-cli for Linux..."; \
						CILIUM_CLI_VERSION=$$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt); \
						CLI_ARCH=amd64; \
						if [ "$$(uname -m)" = "aarch64" ] || [ "$$(uname -m)" = "arm64" ]; then CLI_ARCH=arm64; fi; \
						curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/$${CILIUM_CLI_VERSION}/cilium-linux-$${CLI_ARCH}.tar.gz{,.sha256sum}; \
						sha256sum --check cilium-linux-$${CLI_ARCH}.tar.gz.sha256sum; \
						sudo tar xzvfC cilium-linux-$${CLI_ARCH}.tar.gz /usr/local/bin; \
						rm cilium-linux-$${CLI_ARCH}.tar.gz{,.sha256sum}; \
						;; \
					kubectl) \
						echo "[deps] Installing kubectl for Linux..."; \
						if command -v apt-get >/dev/null 2>&1; then \
							sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gnupg; \
							curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg; \
							echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list; \
							sudo apt-get update && sudo apt-get install -y kubectl; \
						else \
							curl -LO "https://dl.k8s.io/release/$$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"; \
							sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl; \
							rm kubectl; \
						fi; \
						;; \
					*) echo "[deps] No Linux install recipe for $$b"; exit 1 ;; \
				esac; \
			else \
				echo "[deps] Unsupported OS: $(OS_UNAME)"; \
				exit 1; \
			fi; \
			if ! command -v $$b >/dev/null 2>&1; then \
				echo "[deps] Installation of $$b appears to have failed."; exit 1; \
			else \
				echo "[deps] Successfully installed $$b."; \
			fi; \
		else \
			echo "[deps] Missing required binary: $$b"; \
			if [ "$(OS_UNAME)" = "Darwin" ] && [ "$(HAVE_BREW)" != "1" ]; then \
				echo "[deps] Homebrew not found. Install from https://brew.sh/ or install $$b manually."; \
			elif [ "$(OS_UNAME)" = "Linux" ]; then \
				echo "[deps] Please install $$b manually or run with SKIP_AUTO_INSTALL=0"; \
			fi; \
			if [ "$(SKIP_AUTO_INSTALL)" = "1" ]; then \
				echo "[deps] Auto-install skipped (SKIP_AUTO_INSTALL=1)."; \
			fi; \
			exit 1; \
		fi; \
	done
	@echo "[deps] Checking Docker availability..."
	@if ! command -v docker >/dev/null 2>&1; then \
		echo "[deps] ❌ Docker is not installed."; \
		if [ "$(OS_UNAME)" = "Darwin" ]; then \
			echo "[deps] Please install Docker Desktop from https://docs.docker.com/desktop/install/mac-install/"; \
		elif [ "$(OS_UNAME)" = "Linux" ]; then \
			echo "[deps] Please install Docker from https://docs.docker.com/engine/install/"; \
		fi; \
		exit 1; \
	elif ! docker info >/dev/null 2>&1; then \
		echo "[deps] ❌ Docker is installed but not running."; \
		if [ "$(OS_UNAME)" = "Darwin" ]; then \
			echo "[deps] Please start Docker Desktop application."; \
		elif [ "$(OS_UNAME)" = "Linux" ]; then \
			echo "[deps] Please start Docker daemon: sudo systemctl start docker"; \
		fi; \
		exit 1; \
	else \
		echo "[deps] ✓ Docker is running"; \
	fi
endif

# ---- Helpers (shell checks embedded in targets) ----
# "Cluster exists" if either talosctl knows it OR a talos context matches the name (or name-<n>)
CHECK_CLUSTER_EXISTS_CMD = talosctl cluster show --name $(CLUSTER_NAME) >/dev/null 2>&1 || \
   talosctl config contexts 2>/dev/null | awk 'NR>1 {gsub(/^\*/,"",$$1); print $$1}' | grep -qE '^$(CLUSTER_NAME)(-[0-9]+)?$$'

create-cluster: deps ## Create Talos cluster (override CONTROLPLANES=X WORKERS=Y) (no-op if exists)
	@echo "[create] Checking if cluster '$(CLUSTER_NAME)' already exists..."
	@if talosctl cluster show --name $(CLUSTER_NAME) 2>/dev/null | grep -q "NAME.*$(CLUSTER_NAME)" && \
	   [ "$$(talosctl cluster show --name $(CLUSTER_NAME) 2>/dev/null | awk '/NODES:/,EOF {if($$1 != "" && $$1 != "NODES:" && $$1 != "NAME") print "running"; exit}')" = "running" ]; then \
		echo "[create] Cluster $(CLUSTER_NAME) already exists with running nodes; skipping."; \
		talosctl cluster show --name $(CLUSTER_NAME); \
		exit 0; \
	else \
		echo "[create] Cluster $(CLUSTER_NAME) not found or not running; creating..."; \
		echo "[create] Cleaning up any stale contexts..."; \
		talosctl config contexts 2>/dev/null | awk 'NR>1 {gsub(/^\*/,"",$$1); print $$1}' | grep -E '^$(CLUSTER_NAME)' | xargs -I {} talosctl config remove {} --force 2>/dev/null || true; \
		talosctl cluster create --name $(CLUSTER_NAME) \
			--controlplanes $(CONTROLPLANES) \
			--workers $(WORKERS) \
			--cpus $(CONTROLPLANE_CPUS) \
			--memory $(CONTROLPLANE_MEMORY) \
			--cpus-workers $(WORKER_CPUS) \
			--memory-workers $(WORKER_MEMORY) \
			--config-patch @talos/patch.yaml \
			--skip-k8s-node-readiness-check; \
	fi

destroy-cluster: ## Destroy Talos cluster
	@echo "[destroy] Destroying cluster $(CLUSTER_NAME)..."
	@talosctl cluster destroy --name $(CLUSTER_NAME)
	@echo "[destroy] Cluster $(CLUSTER_NAME) destroyed."
	@echo "[destroy] Cleaning up kubectl contexts and clusters..."
	@kubectl config get-contexts -o name | grep -E "admin@$(CLUSTER_NAME)" | xargs -I {} kubectl config delete-context {} 2>/dev/null || true
	@kubectl config get-clusters | grep -E "^$(CLUSTER_NAME)" | xargs -I {} kubectl config delete-cluster {} 2>/dev/null || true
	@echo "[destroy] Cleaning up Talos contexts..."
	@talosctl config contexts 2>/dev/null | awk 'NR>1 {gsub(/^\*/,"",$$1); print $$1}' | grep -E '^$(CLUSTER_NAME)(-[0-9]+)?$$' | xargs -I {} talosctl config remove {} -y 2>/dev/null || true
	@echo "[destroy] Unsetting kubectl current context..."
	@kubectl config unset current-context 2>/dev/null || true
	@echo "[destroy] All contexts and clusters cleaned up."

deploy: deps ## Generate manifests & deploy core stack (no-op if already deployed)
	@echo "[deploy] Checking for existing Cilium installation..."
	@if cilium status >/dev/null 2>&1; then \
		echo "[deploy] Cilium is already running; skipping installation."; \
		cilium status; \
		exit 0; \
	else \
		echo "[deploy] Rendering Cilium manifests (dry-run) -> deploy/00-core/cilium-manifests.yaml"; \
		mkdir -p deploy/00-core; \
		echo "[deploy] Generating and applying Cilium manifests..."; \
		cilium install --values cilium/cilium-values.yaml --dry-run > deploy/00-core/cilium-manifests.yaml; \
		kubectl apply -k deploy/00-core; \
		kubectl -n kube-system rollout status ds/cilium --timeout=5m; \
		kubectl -n kube-system rollout status deploy/cilium-operator --timeout=5m; \
		echo "[deploy] Waiting for Hubble components..."; \
		kubectl -n kube-system rollout status deploy/hubble-relay --timeout=5m; \
		kubectl -n kube-system rollout status deploy/hubble-ui --timeout=5m; \
		echo "[deploy] Generated Cilium manifests applied."; \
		echo "[deploy] Waiting for all Cilium pods to be ready..."; \
		kubectl -n kube-system wait --for=condition=Ready pods -l k8s-app=cilium --timeout=5m; \
		kubectl -n kube-system wait --for=condition=Ready pods -l k8s-app=hubble-relay --timeout=5m; \
		kubectl -n kube-system wait --for=condition=Ready pods -l k8s-app=hubble-ui --timeout=5m; \
		echo "[deploy] Checking Cilium status..."; \
		cilium status; \
	fi

clean: destroy-cluster ## Clean up everything