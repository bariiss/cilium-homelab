CLUSTER_NAME ?= talos-home
CONTROLPLANES ?= 1
WORKERS ?= 1

# QEMU-based Talos cluster configuration
# Specific resource allocation for control plane nodes
CONTROLPLANE_CPUS ?= 4
CONTROLPLANE_MEMORY ?= 4096

# Specific resource allocation for worker nodes  
WORKER_CPUS ?= 4
WORKER_MEMORY ?= 4096

# QEMU-specific settings
DISK_SIZE ?= 6144
NETWORK_CIDR ?= 10.5.0.0/24
TALOS_VERSION ?= v1.11.1

# Platform detection (auto-detect or override with ARCH=amd64/arm64)
UNAME_ARCH := $(shell uname -m)
ifeq ($(UNAME_ARCH),x86_64)
    ARCH ?= amd64
else ifeq ($(UNAME_ARCH),arm64)
    ARCH ?= arm64
else ifeq ($(UNAME_ARCH),aarch64)
    ARCH ?= arm64
else
    ARCH ?= amd64
endif

ISO_PATH ?= _out/talos-$(TALOS_VERSION)-$(ARCH).iso

# Kernel and initramfs paths (faster than ISO boot)
VMLINUZ_PATH ?= _out/vmlinuz-$(ARCH)
INITRAMFS_PATH ?= _out/initramfs-$(ARCH).xz

# Registry mirrors (optional, set REGISTRY_MIRRORS env var)
REGISTRY_MIRRORS ?= $(shell echo $$REGISTRY_MIRRORS)

# Optional: set to 1 to skip automatic dependency installation attempts
SKIP_AUTO_INSTALL ?= 0

# Core CLI dependencies required for targets
REQUIRED_BINS = talosctl kubectl cilium

# QEMU binary selection based on architecture
ifeq ($(ARCH),amd64)
    QEMU_BIN = qemu-system-x86_64
else ifeq ($(ARCH),arm64)
    QEMU_BIN = qemu-system-aarch64
else
    QEMU_BIN = qemu-system-x86_64
endif
QEMU_BINS = qemu-system-x86_64 qemu-system-aarch64

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
							curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg; \
							echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list; \
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
	@echo "[deps] Checking QEMU availability for $(ARCH) architecture..."; \
	if command -v $(QEMU_BIN) >/dev/null 2>&1; then \
		echo "[deps] ✓ $(QEMU_BIN) is available"; \
		QEMU_FOUND=1; \
	else \
		echo "[deps] $(QEMU_BIN) not found, checking for any QEMU binary..."; \
		QEMU_FOUND=0; \
		for qemu_bin in $(QEMU_BINS); do \
			if command -v $$qemu_bin >/dev/null 2>&1; then \
				echo "[deps] ✓ $$qemu_bin is available"; \
				QEMU_FOUND=1; \
				break; \
			fi; \
		done; \
	fi; \
	if [ $$QEMU_FOUND -eq 0 ] && [ "$(SKIP_AUTO_INSTALL)" = "0" ]; then \
		echo "[deps] Installing QEMU..."; \
		if [ "$(OS_UNAME)" = "Darwin" ] && [ "$(HAVE_BREW)" = "1" ]; then \
			brew install qemu; \
		elif [ "$(OS_UNAME)" = "Linux" ]; then \
			if command -v apt-get >/dev/null 2>&1; then \
				sudo apt-get update && sudo apt-get install -y qemu-system-x86 qemu-system-arm qemu-utils; \
			elif command -v yum >/dev/null 2>&1; then \
				sudo yum install -y qemu-kvm qemu-system-x86 qemu-system-aarch64; \
			elif command -v pacman >/dev/null 2>&1; then \
				sudo pacman -S qemu-base qemu-system-x86 qemu-system-aarch64; \
			else \
				echo "[deps] Please install QEMU manually"; exit 1; \
			fi; \
		else \
			echo "[deps] Please install QEMU manually for $(OS_UNAME)"; exit 1; \
		fi; \
	elif [ $$QEMU_FOUND -eq 0 ]; then \
		echo "[deps] ❌ QEMU is not installed. Please install QEMU or set SKIP_AUTO_INSTALL=0"; \
		exit 1; \
	fi
endif

# ---- Helpers (shell checks embedded in targets) ----
# "Cluster exists" if either talosctl knows it OR a talos context matches the name (or name-<n>)
CHECK_CLUSTER_EXISTS_CMD = talosctl cluster show --name $(CLUSTER_NAME) >/dev/null 2>&1 || \
   talosctl config contexts 2>/dev/null | awk 'NR>1 {gsub(/^\*/,"",$$1); print $$1}' | grep -qE '^$(CLUSTER_NAME)(-[0-9]+)?$$'

create-cluster: deps download-kernel ## Create QEMU-based Talos cluster (override ARCH=amd64/arm64 CONTROLPLANES=X WORKERS=Y) (no-op if exists)
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "[create] QEMU requires root privileges for HVF acceleration."; \
		echo "[create] Please run: sudo -E make create-cluster"; \
		exit 1; \
	fi
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
			--provisioner qemu \
			--controlplanes $(CONTROLPLANES) \
			--workers $(WORKERS) \
			--cpus $(CONTROLPLANE_CPUS) \
			--memory $(CONTROLPLANE_MEMORY) \
			--cpus-workers $(WORKER_CPUS) \
			--memory-workers $(WORKER_MEMORY) \
			--cidr $(NETWORK_CIDR) \
			--disk $(DISK_SIZE) \
			--vmlinuz-path $(VMLINUZ_PATH) \
			--initrd-path $(INITRAMFS_PATH) \
			--config-patch @talos/patch.yaml \
			--skip-k8s-node-readiness-check \
			$(REGISTRY_MIRRORS); \
	fi

download-kernel: ## Download Talos kernel and initramfs for QEMU (faster than ISO)
	@mkdir -p _out
	@if [ ! -f "$(VMLINUZ_PATH)" ]; then \
		echo "[kernel] Downloading vmlinuz $(TALOS_VERSION) for $(ARCH)..."; \
		curl -L "https://github.com/siderolabs/talos/releases/download/$(TALOS_VERSION)/vmlinuz-$(ARCH)" -o "$(VMLINUZ_PATH)"; \
		echo "[kernel] Downloaded $(VMLINUZ_PATH)"; \
	else \
		echo "[kernel] vmlinuz already exists: $(VMLINUZ_PATH)"; \
	fi
	@if [ ! -f "$(INITRAMFS_PATH)" ]; then \
		echo "[kernel] Downloading initramfs $(TALOS_VERSION) for $(ARCH)..."; \
		curl -L "https://github.com/siderolabs/talos/releases/download/$(TALOS_VERSION)/initramfs-$(ARCH).xz" -o "$(INITRAMFS_PATH)"; \
		echo "[kernel] Downloaded $(INITRAMFS_PATH)"; \
	else \
		echo "[kernel] initramfs already exists: $(INITRAMFS_PATH)"; \
	fi

download-iso: ## Download Talos ISO image for QEMU (alternative to kernel+initramfs)
	@if [ ! -f "$(ISO_PATH)" ]; then \
		echo "[iso] Downloading Talos ISO $(TALOS_VERSION) for $(ARCH)..."; \
		mkdir -p _out; \
		curl -L "https://github.com/siderolabs/talos/releases/download/$(TALOS_VERSION)/talos-$(ARCH).iso" -o "$(ISO_PATH)"; \
		echo "[iso] Downloaded $(ISO_PATH)"; \
	else \
		echo "[iso] ISO already exists: $(ISO_PATH)"; \
	fi

destroy-cluster: ## Destroy Talos cluster
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "[destroy] QEMU requires root privileges."; \
		echo "[destroy] Please run: sudo -E make destroy-cluster"; \
		exit 1; \
	fi
	@echo "[destroy] Destroying cluster $(CLUSTER_NAME)..."
	@talosctl cluster destroy --name $(CLUSTER_NAME) --provisioner qemu
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
		echo "[deploy] Generating and applying Cilium manifests..."; \
		cilium install --values cilium/cilium-values.yaml --dry-run > deploy/00-core/cilium-manifests.yaml; \
		kubectl apply -k deploy/00-core; \
		kubectl -n kube-system rollout status deploy/cilium-operator --timeout=5m; \
		sleep 10; \
		echo "[deploy] Applying Cilium custom resources..."; \
		kubectl apply -k deploy/01-cilium-custom; \
		echo "[deploy] All components deployed successfully!"; \
		echo "[deploy] Waiting for Cilium to be ready..."; \
		until cilium status --wait; do \
			echo "[deploy] Cilium not ready yet, waiting 10 seconds..."; \
			sleep 10; \
		done; \
		echo "[deploy] Cilium is ready!"; \
	fi

clean: destroy-cluster ## Clean up everything