FROM golang:1.25.7

RUN apt-get update && apt-get install -y \
    libbtrfs-dev \
    make \
    git \
    gcc \
    curl \
    jq \
    pkg-config \
    libseccomp-dev \
    squashfs-tools \
    xz-utils \
    zstd \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Build yq from source (no riscv64 binary available)
RUN go install github.com/mikefarah/yq/v4@latest && \
    cp $(go env GOPATH)/bin/yq /usr/local/bin/yq && \
    yq --version

# Install helm
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Clone k3s
RUN LATEST_TAG=$(curl -s https://api.github.com/repos/k3s-io/k3s/releases/latest | jq -r '.tag_name') && \
    git clone --depth=1 --branch ${LATEST_TAG} https://github.com/k3s-io/k3s.git /k3s

WORKDIR /k3s

# Patch container images for riscv64 compatibility
# Based on https://github.com/CARV-ICS-FORTH/k3s
RUN sed -i 's|rancher/mirrored-pause:3.6|carvicsforth/pause:v3.10-v1.31.1|g' \
        pkg/cli/cmds/const_linux.go && \
    sed -i 's|rancher/klipper-lb:v[0-9.]*|carvicsforth/klipper-lb:v0.4.9|g' \
        pkg/cloudprovider/servicelb.go && \
    sed -i 's|rancher/mirrored-coredns-coredns:[0-9.]*|coredns/coredns:1.11.3|g' \
        manifests/coredns.yaml && \
    sed -i 's|rancher/local-path-provisioner:v[0-9.]*|rancher/local-path-provisioner:v0.0.29|g' \
        manifests/local-storage.yaml && \
    sed -i 's|rancher/mirrored-library-busybox:[0-9.]*|riscv64/busybox:1.36.1|g' \
        manifests/local-storage.yaml && \
    sed -i 's|rancher/mirrored-metrics-server:v[0-9.]*|carvicsforth/metrics-server:v0.7.2|g' \
        manifests/metrics-server/metrics-server-deployment.yaml && \
    sed -i 's|repository: "rancher/mirrored-library-traefik"|repository: "traefik"|g' \
        manifests/traefik.yaml && \
    sed -i '/chart: https.*traefik-crd/a\  jobImage: carvicsforth/klipper-helm:v0.9.3-build20241008' \
        manifests/traefik.yaml && \
    sed -i '/chart: https.*traefik-[^c]/a\  jobImage: carvicsforth/klipper-helm:v0.9.3-build20241008' \
        manifests/traefik.yaml

# Download static charts and dependencies
RUN mkdir -p build/data build/static pkg/static/embed && \
    ./scripts/download

# Copy charts to embed directory
RUN cp -r build/static/charts pkg/static/embed/charts

# Build k3s for riscv64
RUN GOARCH=riscv64 \
    GOOS=linux \
    SKIP_VALIDATE=true \
    SKIP_IMAGE=true \
    SKIP_AIRGAP=true \
    ./scripts/build

# Build flannel CNI plugin
RUN mkdir -p /output/cni && \
    git clone --depth=1 --branch v1.9.0-flannel1 \
    https://github.com/flannel-io/cni-plugin.git /flannel-cni && \
    cd /flannel-cni && \
    GOARCH=riscv64 CGO_ENABLED=0 go build -o /output/cni/flannel .

RUN cp /k3s/bin/k3s /output/k3s

FROM scratch
COPY --from=0 /output/k3s /k3s
COPY --from=0 /output/cni/ /cni/
ENTRYPOINT ["/k3s"]