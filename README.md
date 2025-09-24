# Cilium HomeLab

A streamlined homelab setup for running a local Kubernetes cluster using Talos OS with Cilium CNI, designed for development, testing, and learning purposes.

## 🏗️ Architecture

This project provides a complete local Kubernetes environment with:

- **Talos OS**: Immutable, minimal, and secure Kubernetes distribution
- **Cilium**: High-performance Container Network Interface (CNI) with eBPF
- **Hubble**: Network observability platform built on top of Cilium
- **Gateway API**: Next-generation ingress and traffic management
- **Metrics Server**: Resource usage metrics collection

## 📁 Project Structure

```text
cilium-homelab/
├── Makefile                    # Main automation and build targets
├── .gitignore                  # Git ignore patterns for secrets and generated files
├── cilium/
│   └── cilium-values.yaml      # Cilium configuration values
├── deploy/
│   └── 00-core/
│       ├── cilium-manifests.yaml    # Generated Cilium manifests (auto-generated)
│       └── kustomization.yaml       # Kustomize configuration for core components
└── talos/
    └── patch.yaml              # Talos cluster configuration patches
```

### Directory Details

#### `cilium/`

Contains Cilium-specific configuration:

- **`cilium-values.yaml`**: Helm values for Cilium installation with Hubble UI, kube-proxy replacement, and Prometheus metrics enabled

#### `deploy/00-core/`

Core Kubernetes manifests and configurations:

- **`cilium-manifests.yaml`**: Auto-generated Cilium installation manifests (created by `make deploy`)
- **`kustomization.yaml`**: Kustomize configuration that includes:
  - Cilium manifests
  - Gateway API CRDs (v1.1.0)
  - Metrics Server components
  - Patches for metrics-server to work with kubelet insecure TLS

#### `talos/`

Talos OS specific configurations:

- **`patch.yaml`**: Cluster configuration patches that:
  - Disable default CNI (to use Cilium)
  - Disable kube-proxy (replaced by Cilium)
  - Configure network settings for local development

## 🚀 Quick Start

Get your Cilium homelab up and running in minutes! Simply clone the repository and run a single command.

### Prerequisites

The Makefile will automatically install required dependencies and verify system requirements:

**Required:**

- **Docker** - Must be installed and running (verified automatically)

**Auto-installed if missing:**

- `talosctl` - Talos cluster management CLI
- `kubectl` - Kubernetes CLI  
- `cilium` - Cilium CLI for network management

**Platform Support:**

- **macOS**: Uses Homebrew for installation  
- **Linux (Ubuntu/Debian)**: Uses official installation methods and package managers

### Installation

1. **Clone the repository:**

   ```bash
   git clone https://github.com/bariiss/cilium-homelab.git
   cd cilium-homelab
   ```

   That's it! No complex setup required - everything is automated through the Makefile.

### Basic Usage

1. **Create a cluster:**

   ```bash
   make create-cluster
   ```

   This creates a Talos cluster with 1 control plane node and 1 worker node (default configuration).

2. **Deploy Cilium and core components:**

   ```bash
   make deploy
   ```

   This installs Cilium CNI, Hubble, Gateway API CRDs, and metrics server.

3. **Verify the installation:**

   ```bash
   kubectl get nodes
   kubectl get pods -n kube-system
   cilium status
   ```

4. **Clean up:**

   ```bash
   make clean
   ```

### Advanced Usage

#### Custom Cluster Configuration

**Override cluster size:**

```bash
make create-cluster CONTROLPLANES=2 WORKERS=3
```

**Configure resource allocation:**

```bash
make create-cluster CPUS=4 MEMORY=8192  # 4 CPUs, 8GB RAM per node
```

**Combine multiple parameters:**

```bash
make create-cluster CONTROLPLANES=1 WORKERS=2 CPUS=2 MEMORY=6144
```

**Skip automatic dependency installation:**

```bash
make create-cluster SKIP_AUTO_INSTALL=1
```

#### Available Make Targets

- `help` - Show available targets with descriptions
- `deps` - Verify and install required CLI tools
- `create-cluster` - Create Talos cluster (idempotent - skips if already exists)
- `destroy-cluster` - Destroy the cluster and clean all contexts (comprehensive cleanup)
- `deploy` - Deploy Cilium and core components (requires running cluster)
- `clean` - Complete cleanup (destroys cluster)

#### Configuration Parameters

All parameters can be overridden when running make targets:

| Parameter | Default | Description | Example Values |
|-----------|---------|-------------|----------------|
| `CLUSTER_NAME` | `talos-home` | Name of the cluster | `my-cluster` |
| `CONTROLPLANES` | `1` | Number of control plane nodes | `1`, `2`, `3` |
| `WORKERS` | `1` | Number of worker nodes | `1`, `2`, `3`, `4` |
| `CPUS` | `4` | CPU cores per node | `1`, `2`, `4`, `8` |
| `MEMORY` | `4096` | Memory in MB per node | `2048` (2GB), `8192` (8GB) |
| `SKIP_AUTO_INSTALL` | `0` | Skip automatic tool installation | `0` (install), `1` (skip) |

## 🔧 Configuration Details

### Cluster Configuration

**Default Settings:**

- Cluster name: `talos-home`
- Control planes: 1 node
- Workers: 1 node  
- CPUs per node: 4 cores
- Memory per node: 4096MB (4GB)
- Network: Docker-based local cluster
- CNI: Disabled (Cilium replaces it)
- Kube-proxy: Disabled (Cilium kube-proxy replacement)

### Cilium Features

**Enabled Features:**

- ✅ Kube-proxy replacement
- ✅ Hubble observability platform
- ✅ Hubble Relay for multi-node visibility
- ✅ Hubble UI for network visualization
- ✅ Prometheus metrics collection
- ✅ Host networking mode for performance
- ✅ eBPF-based networking and security

**Configuration Highlights:**

- IPAM mode: Kubernetes (integrates with K8s networking)
- Security context: Comprehensive capabilities for eBPF operations
- Cgroup auto-mount disabled (Talos handles this)
- Custom Kubernetes API server endpoint configuration

### Gateway API Integration

The deployment includes Gateway API v1.1.0 CRDs:

- `GatewayClass` - Define gateway implementations
- `Gateway` - Configure load balancers and ingress points
- `HTTPRoute` - HTTP traffic routing rules
- `GRPCRoute` - gRPC traffic routing
- `TLSRoute` - TLS traffic handling
- `ReferenceGrant` - Cross-namespace resource references

## 🔍 Observability

### Hubble UI

Access the Hubble UI for network observability:

```bash
cilium hubble ui
```

### Metrics

Cilium metrics are available on port 9090:

```bash
kubectl port-forward -n kube-system svc/cilium-agent 9090:9090
```

### Cluster Resource Usage

View resource consumption with metrics-server:

```bash
kubectl top nodes
kubectl top pods -A
```

## � System Requirements

### Supported Operating Systems

- **macOS**: Automatic dependency installation via Homebrew
- **Linux**: Ubuntu 20.04+, Debian 11+, or compatible distributions
- **Prerequisites**: Docker installed and running

### Automatic Installation Support

| Tool | macOS (Homebrew) | Linux |
|------|------------------|-------|
| `talosctl` | ✅ siderolabs/tap | ✅ Official installer |
| `kubectl` | ✅ kubernetes-cli | ✅ Official Kubernetes APT repo |
| `cilium` | ✅ cilium-cli | ✅ GitHub releases |

## �🛠️ Troubleshooting

### Common Issues

1. **Cluster creation fails:**
   - Ensure Docker is running
   - Check if required ports are available
   - Verify sufficient system resources

2. **Dependency installation issues (Linux):**
   - Ensure you have `sudo` privileges
   - Check internet connectivity for downloads
   - For Ubuntu/Debian: `sudo apt-get update` before running
   - Manual installation: Set `SKIP_AUTO_INSTALL=1` and install tools manually

3. **Cilium installation issues:**
   - Ensure cluster is running: `make create-cluster`
   - Check node readiness: `kubectl get nodes`
   - Review Cilium status: `cilium status`

4. **Network connectivity problems:**
   - Verify Cilium agents are running: `kubectl get pods -n kube-system -l k8s-app=cilium`
   - Check Hubble relay: `kubectl get pods -n kube-system -l k8s-app=hubble-relay`

### Logs and Debugging

**View Cilium logs:**

```bash
kubectl logs -n kube-system -l k8s-app=cilium --tail=50
```

**Check cluster health:**

```bash
# For default 1+1 cluster (1 control plane + 1 worker)
talosctl health --nodes 10.5.0.2,10.5.0.3

# For larger clusters, adjust IP range accordingly
talosctl health --nodes 10.5.0.2,10.5.0.3,10.5.0.4,10.5.0.5
```

**Cilium connectivity test:**

```bash
cilium connectivity test
```

## 🤝 Contributing

This is a homelab environment setup. Feel free to:

- Modify cluster configurations in `talos/patch.yaml`
- Adjust Cilium settings in `cilium/cilium-values.yaml`
- Add additional components to `deploy/00-core/kustomization.yaml`
- Enhance the Makefile with new targets

## 📚 References

- [Talos Documentation](https://www.talos.dev/v1.8/introduction/what-is-talos/)
- [Cilium Documentation](https://docs.cilium.io/)
- [Hubble Observability](https://docs.cilium.io/en/stable/gettingstarted/hubble/)
- [Gateway API](https://gateway-api.sigs.k8s.io/)
- [Kubernetes Metrics Server](https://github.com/kubernetes-sigs/metrics-server)

## 📝 License

This project is for homelab, development and educational purposes. Check individual component licenses for specific terms.
