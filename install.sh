#!/bin/bash
set -e

REPO="12345qwert123456/k3s.RISC-V"
CNI_DIR="/opt/cni/bin"
K3S_BIN="/usr/local/bin/k3s"
K3S_CONFIG="/etc/rancher/k3s/config.yaml"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

if [[ -n "$1" ]]; then
  TAG="$1"
else
  echo "==> Fetching latest release..."
  TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | jq -r '.tag_name')
fi

echo "==> Installing k3s ${TAG} for RISC-V 64..."

# Release tag: v1.35.3-k3s1-riscv64 → archive: k3s-v1.35.3-k3s1-linux-riscv64.tar.gz
ARCHIVE="k3s-${TAG%-riscv64}-linux-riscv64.tar.gz"
URL="https://github.com/${REPO}/releases/download/${TAG}/${ARCHIVE}"

echo "==> Downloading ${ARCHIVE}..."
curl -fL "${URL}" -o "${TMPDIR}/${ARCHIVE}"
tar xzf "${TMPDIR}/${ARCHIVE}" -C "${TMPDIR}"

echo "==> Installing k3s binary..."
sudo install -m 755 "${TMPDIR}/k3s" "${K3S_BIN}"
sudo ln -sf "${K3S_BIN}" /usr/local/bin/kubectl
sudo ln -sf "${K3S_BIN}" /usr/local/bin/crictl
sudo ln -sf "${K3S_BIN}" /usr/local/bin/ctr

echo "==> Installing CNI plugins..."
sudo mkdir -p "${CNI_DIR}"
sudo install -m 755 "${TMPDIR}"/cni/* "${CNI_DIR}/"
echo "Installed CNI plugins: $(ls ${CNI_DIR} | tr '\n' ' ')"

if [[ ! -f "${K3S_CONFIG}" ]]; then
  echo "==> Creating k3s config..."
  sudo mkdir -p /etc/rancher/k3s
  sudo tee "${K3S_CONFIG}" > /dev/null << 'EOF'
disable-cloud-controller: true
pause-image: carvicsforth/pause:v3.10-v1.31.1
EOF
else
  echo "==> Skipping config (${K3S_CONFIG} already exists)"
fi

echo "==> Installing systemd service..."
sudo tee /etc/systemd/system/k3s.service > /dev/null << 'EOF'
[Unit]
Description=Lightweight Kubernetes
Documentation=https://k3s.io
Wants=network-online.target
After=network-online.target

[Service]
Type=notify
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/local/bin/k3s server
KillMode=process
Delegate=yes
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s
Environment="PATH=/opt/cni/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable k3s

echo ""
echo "Installation complete!"
echo ""
echo "Start k3s:"
echo "  sudo systemctl start k3s"
echo ""
echo "Setup kubeconfig:"
echo "  mkdir -p ~/.kube && sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config && sudo chown \$USER ~/.kube/config"
echo ""
echo "Verify:"
echo "  kubectl get pods -A"
