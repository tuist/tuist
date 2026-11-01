# syntax=docker/dockerfile:1.7

# Firecracker guest template for sandboxd (infra/sandboxd/AGENTS.md).
#
# The image's only job is to carry a kernel and an ext4 rootfs onto a node:
# the rootfs is Ubuntu 24.04 with a coding-agent toolchain and four
# guest binaries (sbx-init as PID 1, sbx-agent on vsock, sbx-worker for
# Managed Agents work items, sbx-executor for REAPI actions). There is no systemd.
#
# Stages:
#   builder  compiles the guest binaries (native arch, cross-compiled to amd64)
#   guest    the filesystem the guest boots, assembled with apt
#   rootfs   turns the guest stage into rootfs.ext4 and fetches the kernel
#   final    a small image whose entrypoint installs /template onto the node

ARG KERNEL_URL=https://s3.amazonaws.com/spec.ccfc.min/firecracker-ci/v1.15/x86_64/vmlinux-6.1.155
ARG KERNEL_SHA256=
ARG NODE_MAJOR=22
ARG ANT_VERSION=1.30.0
ARG AMP_VERSION=0.0.1793104576-gc52692
ARG ROOTFS_SIZE=8G
ARG VERSION=dev

FROM --platform=$BUILDPLATFORM golang:1.26.10-alpine3.23 AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY cmd ./cmd
COPY internal ./internal
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    go vet ./... && go test ./...
ARG VERSION
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" -o /out/ ./cmd/...

FROM ubuntu:24.04 AS guest
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash coreutils ca-certificates curl wget git git-lfs openssh-client gnupg sudo tzdata locales \
        iproute2 iputils-ping dnsutils procps psmisc less vim-tiny nano jq ripgrep fd-find unzip zip tar \
        xz-utils zstd bzip2 build-essential pkg-config cmake python3 python3-pip python3-venv \
        e2fsprogs util-linux lsof strace htop tmux rsync sqlite3 libssl-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Node.js from nodesource and the GitHub CLI from its own repo; both signed.
ARG NODE_MAJOR
RUN install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends nodejs gh \
    && rm -rf /var/lib/apt/lists/*

# The Anthropic CLI is the fallback worker when sbx-worker cannot be used.
ARG ANT_VERSION
RUN curl -fsSL --retry 3 -o /tmp/ant.deb \
        "https://github.com/anthropics/anthropic-cli/releases/download/v${ANT_VERSION}/ant_${ANT_VERSION}_linux_amd64.deb" \
    && apt-get update && apt-get install -y --no-install-recommends /tmp/ant.deb \
    && ln -s /usr/ant /usr/local/bin/ant \
    && rm -f /tmp/ant.deb && rm -rf /var/lib/apt/lists/*

# mise for per-project toolchains: shims in scripts, full activation in
# interactive shells.
RUN curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh \
    && cat > /etc/profile.d/mise.sh <<'EOF'
if [ -x /usr/local/bin/mise ]; then
    case "$-" in
        *i*) eval "$(/usr/local/bin/mise activate bash)" ;;
        *) eval "$(/usr/local/bin/mise activate bash --shims)" ;;
    esac
fi
EOF

# Amp's custom-image contract requires a glibc Linux binary and a `user`
# account with passwordless sudo. Pin the CLI and verify its published hash.
ARG AMP_VERSION
RUN curl -fsSL --retry 3 "https://static.ampcode.com/cli/${AMP_VERSION}/amp-linux-x64" -o /usr/local/bin/amp \
    && curl -fsSL --retry 3 "https://static.ampcode.com/cli/${AMP_VERSION}/linux-x64-amp.sha256" -o /tmp/amp.sha256 \
    && echo "$(cat /tmp/amp.sha256)  /usr/local/bin/amp" | sha256sum -c - \
    && chmod 0755 /usr/local/bin/amp && rm /tmp/amp.sha256 \
    && groupadd user && useradd --create-home --gid user --shell /bin/bash user \
    && echo 'user ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/amp-user \
    && chmod 0440 /etc/sudoers.d/amp-user \
    && visudo -cf /etc/sudoers.d/amp-user
COPY --chmod=0755 orb-bootstrap.sh /usr/local/bin/sbx-orb-bootstrap

RUN locale-gen en_US.UTF-8 && update-locale LANG=C.UTF-8 \
    && git lfs install --system --skip-repo \
    && usermod -s /bin/bash root \
    && cat >> /root/.bashrc <<'EOF'

# sandboxd: interactive shells start in the workspace.
case "$-" in *i*) cd /workspace 2>/dev/null ;; esac
EOF
RUN mkdir -p /workspace /mnt/memory /run /tmp /proc /sys /dev \
    && chmod 1777 /tmp \
    && test -x /bin/bash

COPY --from=builder /out/sbx-init /sbin/sbx-init
COPY --from=builder /out/sbx-agent /usr/local/bin/sbx-agent
COPY --from=builder /out/sbx-worker /usr/local/bin/sbx-worker
COPY --from=builder /out/sbx-executor /usr/local/bin/sbx-executor
COPY --chmod=0755 scripts/template-prepare.sh /usr/local/bin/sbx-template-prepare

# Experimental per-image opt-in; account rollout still requires its feature
# flag and this image pin. The root-owned marker is present before snapshotting.
ARG EMBEDDED_EXECUTOR=0
RUN case "$EMBEDDED_EXECUTOR" in \
      0) ;; \
      1) touch /etc/tuist-embedded-executor ;; \
      *) echo "EMBEDDED_EXECUTOR must be 0 or 1" >&2; exit 1 ;; \
    esac

# UID 1000 cannot read the root worker's CAS credential or control sockets.
RUN if ! getent passwd 1000 >/dev/null; then useradd --uid 1000 --create-home builder; fi

# The rootfs stage runs natively: mkfs.ext4 -d produces the same image on any
# host, and this keeps the multi-gigabyte populate step off the emulator.
FROM --platform=$BUILDPLATFORM ubuntu:24.04 AS rootfs
RUN apt-get update && apt-get install -y --no-install-recommends e2fsprogs ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
ARG KERNEL_URL
ARG KERNEL_SHA256
RUN mkdir -p /out \
    && curl -fsSL --retry 3 -o /out/vmlinux "${KERNEL_URL}" \
    && curl -fsSL --retry 3 -o /out/vmlinux.config "${KERNEL_URL}.config" \
    && if [ -n "${KERNEL_SHA256}" ]; then echo "${KERNEL_SHA256}  /out/vmlinux" | sha256sum -c -; fi
COPY --from=guest / /rootfs
ARG ROOTFS_SIZE
# /etc/hostname, hosts and resolv.conf are bind mounts inside a build
# container, so their defaults are seeded here where they are plain files.
# sbx-init rewrites all three at boot.
RUN mkdir -p /rootfs/dev /rootfs/proc /rootfs/sys /rootfs/run /rootfs/tmp /rootfs/workspace /rootfs/mnt/memory \
    && rm -f /rootfs/etc/resolv.conf \
    && echo sandbox > /rootfs/etc/hostname \
    && printf '127.0.0.1\tlocalhost\n127.0.1.1\tsandbox\n::1\tlocalhost ip6-localhost ip6-loopback\n' > /rootfs/etc/hosts \
    && truncate -s "${ROOTFS_SIZE}" /out/rootfs.ext4 \
    && mkfs.ext4 -q -F -L rootfs -d /rootfs -E lazy_itable_init=0,lazy_journal_init=0 /out/rootfs.ext4 \
    && kernel="$(basename "${KERNEL_URL}")" && kernel="${kernel#vmlinux-}" \
    && printf '{"name":"default","kernel":"%s","built_at":"%s","rootfs_bytes":%s}\n' \
        "${kernel}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(stat -c %s /out/rootfs.ext4)" > /out/metadata.json \
    && cat /out/metadata.json && ls -la /out && du -h /out/*

# Build with --target execution-gateway for the stateless public REAPI service.
FROM alpine:3.21 AS execution-gateway
RUN apk add --no-cache ca-certificates
COPY --from=builder /out/reapi-gateway /usr/local/bin/reapi-gateway
USER 65534:65534
EXPOSE 50051
ENTRYPOINT ["/usr/local/bin/reapi-gateway"]

# GNU coreutils for cp --sparse=always: busybox's cp cannot keep holes, and
# a dense copy of the rootfs would cost every node the full 8 GiB.
FROM alpine:3.21
RUN apk add --no-cache coreutils
COPY --from=rootfs /out /template
COPY install-template.sh /install-template.sh
ENTRYPOINT ["/install-template.sh"]
