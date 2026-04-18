# k3s for RISC-V 64

Build and run [k3s](https://k3s.io) on RISC-V 64-bit hardware.

This repository contains a Dockerfile that builds the latest k3s from source with patches to replace container images that don't have official riscv64 support with riscv64-compatible alternatives, based on the work of [CARV-ICS-FORTH](https://github.com/CARV-ICS-FORTH/kubernetes-riscv64).

## Tested on

- [SpacemiT K1](https://www.spacemit.com/) (Orange Pi RV2, Banana Pi F3)
- Ubuntu 24.04 for RISC-V

## Prerequisites

### containerd v2.x

k3s v1.35+ requires containerd v2.x. The system containerd from Ubuntu packages is typically v1.x and is **not compatible**. Install containerd v2.x manually:

```bash
wget https://github.com/containerd/containerd/releases/download/v2.1.6/containerd-2.1.6-linux-riscv64.tar.gz
sudo tar xzf containerd-2.1.6-linux-riscv64.tar.gz -C /usr/local
rm containerd-2.1.6-linux-riscv64.tar.gz
```

```bash
containerd --version
# containerd containerd.io 2.1.6 ...
```

### Other dependencies

```bash
sudo apt-get install -y iptables curl jq
```

> Docker is required only for [Option 3 (Docker Hub)](#option-3-from-docker-hub) or [building from source](#build-from-source).

## What's patched

The following images are replaced with riscv64-compatible versions:

| Original | Replacement |
|---|---|
| `rancher/mirrored-pause:3.6` | `carvicsforth/pause:v3.10-v1.31.1` |
| `rancher/klipper-lb` | `carvicsforth/klipper-lb:v0.4.9` |
| `rancher/klipper-helm` | `carvicsforth/klipper-helm:v0.9.3-build20241008` |
| `rancher/mirrored-coredns-coredns` | `coredns/coredns:1.11.3` |
| `rancher/mirrored-metrics-server` | `carvicsforth/metrics-server:v0.7.2` |
| `rancher/mirrored-library-traefik` | `traefik` |
| `rancher/mirrored-library-busybox` | `riscv64/busybox:1.36.1` |
| `rancher/local-path-provisioner` | `rancher/local-path-provisioner:v0.0.29` |

## Install

### Option 1: Via install.sh (recommended)

Downloads the latest release, installs binaries, creates config and systemd service:

```bash
curl -fsSL https://raw.githubusercontent.com/12345qwert123456/k3s.RISC-V/main/install.sh | bash
```

To install a specific version, pass the release tag as an argument:

```bash
curl -fsSL https://raw.githubusercontent.com/12345qwert123456/k3s.RISC-V/main/install.sh | bash -s v1.35.3-k3s1-riscv64
```

### Option 2: Manual from GitHub Release

```bash
LATEST=$(curl -fsSL https://api.github.com/repos/12345qwert123456/k3s.RISC-V/releases/latest | jq -r '.tag_name')
ARCHIVE="k3s-${LATEST%-riscv64}-linux-riscv64.tar.gz"
curl -fsSL https://github.com/12345qwert123456/k3s.RISC-V/releases/download/${LATEST}/${ARCHIVE} | tar xz

sudo install -m 755 k3s /usr/local/bin/k3s
sudo ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
sudo ln -sf /usr/local/bin/k3s /usr/local/bin/crictl
sudo ln -sf /usr/local/bin/k3s /usr/local/bin/ctr
sudo mkdir -p /opt/cni/bin
sudo install -m 755 cni/* /opt/cni/bin/
```

### Option 3: From Docker Hub

Requires Docker.

```bash
docker pull 12345qwert123456/k3s-riscv64:latest
docker create --name k3s-tmp 12345qwert123456/k3s-riscv64:latest /k3s
docker cp k3s-tmp:/k3s ./k3s
docker cp k3s-tmp:/cni/ ./cni/
docker rm k3s-tmp

sudo install -m 755 k3s /usr/local/bin/k3s
sudo ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
sudo ln -sf /usr/local/bin/k3s /usr/local/bin/crictl
sudo ln -sf /usr/local/bin/k3s /usr/local/bin/ctr
sudo mkdir -p /opt/cni/bin
sudo install -m 755 cni/* /opt/cni/bin/
```

## First start

> If you used `install.sh`, config and systemd service are already created — just start k3s.

```bash
# Create config (skip if install.sh was used)
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/config.yaml << 'EOF'
disable-cloud-controller: true
pause-image: carvicsforth/pause:v3.10-v1.31.1
EOF

# Start k3s
sudo systemctl start k3s

# Setup kubeconfig
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER ~/.kube/config

# Verify
kubectl get pods -A
```

## Build from source

Requires Docker. Builds on the RISC-V device (~45 minutes).

```bash
git clone https://github.com/12345qwert123456/k3s.RISC-V
cd k3s.RISC-V
docker build -t k3s-riscv64 .

docker create --name tmp k3s-riscv64 /k3s
docker cp tmp:/k3s ./k3s
docker cp tmp:/cni/ ./cni/
docker rm tmp

sudo install -m 755 k3s /usr/local/bin/k3s
sudo ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
sudo ln -sf /usr/local/bin/k3s /usr/local/bin/crictl
sudo ln -sf /usr/local/bin/k3s /usr/local/bin/ctr
sudo mkdir -p /opt/cni/bin
sudo install -m 755 cni/* /opt/cni/bin/
```

## GitHub Actions

The workflow:
1. Checks for a new k3s release daily
2. Cross-compiles k3s and CNI plugins for riscv64
3. Pushes the Docker image to Docker Hub
4. Creates a GitHub Release with a `k3s-<version>-linux-riscv64.tar.gz` archive

## Files

| File | Description |
|---|---|
| `Dockerfile` | Builds k3s and all CNI plugins for riscv64 (run on RISC-V device) |
| `install.sh` | Downloads latest release and installs k3s |
| `.github/workflows/build-riscv64.yml` | GitHub Actions workflow |

## Dependencies

- CNI plugins v1.9.1-k3s1 (bridge, host-local, portmap, and more)
- flannel CNI plugin v1.9.0-flannel1
- pause image: [carvicsforth/pause:v3.10-v1.31.1](https://hub.docker.com/r/carvicsforth/pause)

## Credits

- [CARV-ICS-FORTH](https://github.com/CARV-ICS-FORTH/kubernetes-riscv64) — original riscv64 k3s patches and container images
- [k3s-io/k3s](https://github.com/k3s-io/k3s) — upstream k3s project
