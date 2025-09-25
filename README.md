# Talos Cilium HomeLab

A comprehensive homelab setup for running a high-performance Kubernetes cluster using Talos OS with Cilium CNI and advanced networking features. This project includes router DHCP integration, L2 announcements, and ingress-nginx for production-like networking in a local environment.

## 🏗️ Architecture

This project provides a complete Kubernetes environment with advanced networking:

- **Talos OS v1.11.1**: Immutable, minimal, and secure Kubernetes distribution running on QEMU
- **Cilium v1.18.1**: High-performance CNI with eBPF, kube-proxy replacement, and L2 announcements
- **ingress-nginx**: Controller with LoadBalancer service using Cilium L2 announcer
- **Router DHCP Integration**: Cluster nodes get IPs from your home router (10.5.0.x/24)
- **L2 Announcements**: ingress-nginx accessible at 10.5.0.100 on en5 interface
- **Hubble**: Network observability platform with UI
- **Metrics Server**: Resource usage metrics collection

## 📁 Project Structure

```text
cilium-homelab/
├── Makefile                           # QEMU-only automation and build targets
├── README.md                          # This documentation
├── notes.txt                          # Development notes and configuration details
├── _out/                              # Generated kernel images for ARM64
│   ├── initramfs-arm64.xz            # Talos initramfs
│   └── vmlinuz-arm64                 # Talos kernel
├── cilium/
│   └── cilium-values.yaml            # Comprehensive Cilium configuration with L2 announcements
├── deploy/
│   ├── 00-core/                      # Core Kubernetes components (applied first)
│   │   ├── cilium-manifests.yaml    # Generated Cilium manifests (auto-generated)
│   │   └── kustomization.yaml       # Gateway API CRDs, metrics-server, ingress-nginx
│   └── 01-cilium-custom/             # Cilium custom resources (applied after core)
│       ├── cilium-ip-pool.yaml      # LoadBalancer IP pool (10.5.0.100)
│       ├── cilium-l2-policy.yaml    # L2 announcement policy for en5 interface
│       ├── cilium-pod-ip-pool.yaml  # Pod IP pool (10.244.0.0/16)
│       └── kustomization.yaml       # Custom resource deployment configuration
└── talos/
    └── patch.yaml                    # Talos configuration with en5 DHCP networking
```

### Directory Details

#### `cilium/`

Comprehensive Cilium configuration with advanced networking:

- **`cilium-values.yaml`**: Production-ready Cilium configuration featuring:
  - eBPF datapath with kube-proxy replacement
  - L2 announcements for LoadBalancer services
  - Hubble observability with UI and relay
  - BPF optimization with mount disabled (Talos managed)
  - Operator high availability (2 replicas)
  - Integration with Gateway API and metrics collection

#### `deploy/00-core/`

Core Kubernetes components deployed first to establish foundation:

- **`cilium-manifests.yaml`**: Auto-generated Cilium installation manifests
- **`kustomization.yaml`**: Core component orchestration including:
  - Gateway API CRDs (v1.2.0)
  - Metrics Server with kubelet TLS patches
  - ingress-nginx controller with LoadBalancer service
  - External manifests from official sources

#### `deploy/01-cilium-custom/`

Cilium custom resources deployed after core components are ready:

- **`cilium-ip-pool.yaml`**: LoadBalancer IP pool configuration (10.5.0.100/32)
- **`cilium-l2-policy.yaml`**: L2 announcement policy for en5 interface
- **`cilium-pod-ip-pool.yaml`**: Pod CIDR configuration (10.244.0.0/16)
- **`kustomization.yaml`**: Custom resource deployment coordination

#### `talos/`

Talos OS configuration optimized for Cilium networking:

- **`patch.yaml`**: Advanced cluster configuration featuring:
  - en5 interface with router DHCP integration (10.5.0.x/24)
  - CNI and kube-proxy disabled for Cilium replacement  
  - Bridge networking sysctls for container communication
  - Cluster network configuration (10.5.0.0/24)

#### `_out/`

Generated Talos OS kernel images for ARM64 architecture:

- **`initramfs-arm64.xz`**: Compressed initial RAM filesystem
- **`vmlinuz-arm64`**: Linux kernel image optimized for Talos

## 🚀 Quick Start

Get your Cilium homelab up and running in minutes! Simply clone the repository and run a single command.

### Prerequisites

The Makefile will automatically install required dependencies and verify system requirements:

**Required:**

- **QEMU** - Virtualization platform (automatically installed if missing)
- **Router DHCP** - Your home router must provide DHCP for 10.5.0.x/24 network

**Auto-installed if missing:**

- `talosctl` - Talos cluster management CLI
- `kubectl` - Kubernetes CLI  
- `cilium` - Cilium CLI for network management
- `qemu-system-aarch64` - ARM64 emulation support

**Platform Support:**

- **macOS**: Uses Homebrew for all installations
- **Linux (Ubuntu/Debian)**: Uses official installation methods and package managers

**Network Requirements:**

- **VMNet Interface**: en5 interface available for QEMU bridge networking and L2 announcements
- **IP Range**: 10.5.0.100 must be available for ingress-nginx LoadBalancer
- **Router Network**: 10.5.0.x/24 DHCP range configured on your router

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

   This creates a Talos cluster using QEMU with ARM64 architecture. Nodes will get IPs from your router's DHCP (10.5.0.x/24).

2. **Deploy components in two phases:**

   ```bash
   make deploy
   ```

   This deploys in two phases:
   - **Phase 1**: Core components (Gateway API CRDs, metrics-server, ingress-nginx, Cilium)
   - **Phase 2**: Cilium custom resources (IP pools, L2 announcements)

   After deployment, ingress-nginx will be accessible at **10.5.0.100** via L2 announcements.

3. **Verify the installation:**

   ```bash
   kubectl get nodes
   kubectl get pods -n kube-system
   cilium status
   ```

4. **Access ingress-nginx:**

   ```bash
   # Check LoadBalancer IP assignment
   kubectl get svc -n ingress-nginx
   
   # Test connectivity (should respond with 404 - no backend configured)
   curl http://10.5.0.100
   
   # View L2 announcement status
   kubectl get l2announcementpolicy -o yaml
   ```

5. **Clean up:**

   ```bash
   make clean
   ```

### Usage with Elevated Privileges

If you encounter permission issues or need elevated privileges for QEMU operations, use the following commands:

1. **Complete workflow with sudo:**

   ```bash
   # Create cluster with elevated privileges
   sudo -E make create-cluster
   
   # Deploy components (usually doesn't require sudo)
   make deploy
   
   # Destroy cluster when done
   sudo -E make destroy-cluster
   ```

   The `-E` flag preserves your environment variables, ensuring tools like kubectl maintain access to your user's kube config.

2. **Step-by-step with elevated privileges:**

   ```bash
   # Step 1: Create the cluster
   sudo -E make create-cluster
   
   # Step 2: Verify cluster is running
   kubectl get nodes
   
   # Step 3: Deploy all components
   make deploy
   
   # Step 4: Verify deployment
   kubectl get pods -A
   cilium status
   
   # Step 5: Test ingress connectivity
   curl http://<YOUR-LB-L2-IP>
   
   # Step 6: Clean up when done
   sudo -E make destroy-cluster
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

**Use different VMNet interface:**

```bash
make create-cluster TALOS_QEMU_VMNET_IFNAME=eth0  # Use eth0 instead of en5
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
| `TALOS_QEMU_VMNET_IFNAME` | `en5` | VMNet interface for QEMU bridge networking | `en0`, `eth0`, `br0` |
| `TALOSCTL_BIN` | `/path/to/local/talosctl` | Custom talosctl binary path | `/usr/local/bin/talosctl` |
| `SKIP_AUTO_INSTALL` | `0` | Skip automatic tool installation | `0` (install), `1` (skip) |

## 🔧 Configuration Details

### Cluster Configuration

**Default Settings:**

- Cluster name: `talos-home`
- Architecture: ARM64 (QEMU virtualization)
- Control planes: 1 node
- Workers: 1 node  
- CPUs per node: 4 cores
- Memory per node: 4096MB (4GB)
- CNI: Disabled (Cilium replaces it)
- Kube-proxy: Disabled (Cilium kube-proxy replacement)

### Network Architecture

**Multi-tier networking configuration:**

- **Router Network**: 10.5.0.x/24 (DHCP from home router)
  - Talos nodes get IPs automatically from router DHCP
  - Interface: en5 with DHCP client configuration
- **Cluster Network**: 10.5.0.0/24 (internal cluster communication)
  - Control plane: 10.5.0.2
  - Worker nodes: 10.5.0.3+
- **Pod Network**: 10.244.0.0/16 (managed by Cilium)
  - Automatic pod IP allocation
  - eBPF-based routing and security
- **LoadBalancer IP**: 10.5.0.100/32
  - ingress-nginx controller accessible from host network
  - L2 announcements via en5 interface

### Cilium Features

**Enabled Features:**

- ✅ Kube-proxy replacement with eBPF acceleration
- ✅ L2 announcements for LoadBalancer services
- ✅ Hubble observability platform with UI and metrics
- ✅ Hubble Relay for multi-node visibility
- ✅ Prometheus metrics and monitoring integration
- ✅ BPF optimization with Talos-specific tuning
- ✅ High availability operator (2 replicas)
- ✅ Pod IP pool management (10.244.0.0/16)

**Advanced Configuration:**

- **Datapath Mode**: veth (compatibility with Talos)
- **Routing Mode**: tunnel (encapsulated pod-to-pod communication)
- **IPAM Mode**: Kubernetes with custom IP pools
- **L2 Announcements**: Enabled for en5 interface
- **BPF Mount**: Disabled (Talos OS manages BPF filesystem)
- **Security Context**: Comprehensive capabilities for eBPF operations
- **Custom Resources**: LoadBalancerIPPool, L2AnnouncementPolicy, PodIPPool

### ingress-nginx Integration

**LoadBalancer Configuration:**

- **Service Type**: LoadBalancer (uses Cilium L2 announcements)
- **External IP**: 10.5.0.100 (announced via L2 on en5 interface)
- **High Availability**: Ready for multi-node deployments
- **SSL Termination**: Supports TLS/SSL certificates
- **Backend Protocol**: HTTP/HTTPS with configurable timeouts

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

## 💻 System Requirements

### Supported Operating Systems

- **macOS**: Automatic dependency installation via Homebrew
- **Linux**: Ubuntu 20.04+, Debian 11+, or compatible distributions with KVM support
- **Prerequisites**:
  - QEMU with ARM64 emulation support and VMNet framework
  - Router with DHCP configured for 10.5.0.x/24 network  
  - Network interface en5 available for VMNet bridge and L2 announcements

### Hardware Requirements

- **CPU**: x86_64 or ARM64 processor with virtualization support
- **Memory**: 8GB+ RAM recommended (4GB minimum for single-node cluster)
- **Storage**: 10GB+ free disk space for images and cluster data
- **Network**: Access to home router DHCP and unused IP 10.5.0.100

### Automatic Installation Support

| Tool | macOS (Homebrew) | Linux |
|------|------------------|-------|
| `talosctl` | ✅ siderolabs/tap | ✅ Official installer |
| `kubectl` | ✅ kubernetes-cli | ✅ Official Kubernetes APT repo |
| `cilium` | ✅ cilium-cli | ✅ GitHub releases |
| `qemu-system-aarch64` | ✅ qemu | ✅ Official package managers |

## 🛠️ Troubleshooting

### Common Issues

1. **Cluster creation fails:**
   - Ensure QEMU is installed and functioning
   - Verify ARM64 emulation support: `qemu-system-aarch64 --version`
   - Check if router DHCP is working on 10.5.0.x/24 network
   - Verify sufficient system resources (8GB+ RAM recommended)

2. **Network connectivity problems:**
   - Verify en5 interface exists: `ip addr show en5` or `ifconfig en5`
   - Check router DHCP range includes 10.5.0.x addresses
   - Ensure 10.5.0.100 is not in use by other devices
   - Verify L2 announcements: `cilium bgp peers` (should show L2 announcements)

3. **Dependency installation issues (Linux):**
   - Ensure you have `sudo` privileges for QEMU installation
   - Check internet connectivity for downloads
   - For Ubuntu/Debian: `sudo apt-get update` before running
   - Manual installation: Set `SKIP_AUTO_INSTALL=1` and install tools manually

4. **Cilium L2 announcement issues:**
   - Verify L2AnnouncementPolicy is applied: `kubectl get l2announcementpolicy`
   - Check LoadBalancerIPPool status: `kubectl get loadbalancerippool`
   - Ensure Cilium L2 announcements are enabled: `cilium config view | grep l2-announcements`
   - Test connectivity to 10.5.0.100: `ping 10.5.0.100`

5. **ingress-nginx LoadBalancer issues:**
   - Check service external IP assignment: `kubectl get svc -n ingress-nginx`
   - Verify Cilium operator status: `kubectl get pods -n kube-system -l name=cilium-operator`
   - Review ingress controller logs: `kubectl logs -n ingress-nginx deployment/ingress-nginx-controller`

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

This is an advanced homelab environment setup featuring production-like networking. Feel free to:

- Modify cluster configurations in `talos/patch.yaml` (network interfaces, DHCP settings)
- Adjust Cilium settings in `cilium/cilium-values.yaml` (L2 announcements, BPF options)
- Add additional components to `deploy/00-core/kustomization.yaml` (new services, ingress rules)
- Customize LoadBalancer IP pools in `deploy/01-cilium-custom/cilium-ip-pool.yaml`
- Enhance the Makefile with new QEMU or networking targets

## 📚 References

- [Talos Documentation v1.11.1](https://www.talos.dev/v1.11/introduction/what-is-talos/)
- [Cilium Documentation v1.18.1](https://docs.cilium.io/en/v1.18/)
- [Cilium L2 Announcements](https://docs.cilium.io/en/stable/network/l2-announcements/)
- [Hubble Observability](https://docs.cilium.io/en/stable/gettingstarted/hubble/)
- [Gateway API v1.2.0](https://gateway-api.sigs.k8s.io/)
- [ingress-nginx Controller](https://kubernetes.github.io/ingress-nginx/)
- [Kubernetes Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [QEMU ARM64 Emulation](https://qemu.readthedocs.io/en/latest/system/target-arm.html)

## 📝 License

This project is for homelab, development and educational purposes. Check individual component licenses for specific terms.
