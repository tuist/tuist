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
ARG AGENT_BROWSER_VERSION=0.38.1
# Amp Desktop's compositor and streamer (labwc, waymote) as Amp's x64 orb image
# ships them in /opt/amp-wayland. That image builds the directory in its own
# layer, so the template fetches only that blob (about 6 MB), pinned by its
# digest, rather than the 1.8 GB image. To update, read the newest
# amp-orb:latest amd64 manifest and take the layer whose history line is
# `COPY /opt/amp-wayland /opt/amp-wayland`. Its only GPL component is labwc
# 0.9.8 (GPL-2.0, source at https://github.com/labwc/labwc/tree/0.9.8); the
# rest is MIT: wlroots, wayland, libdrm, pixman, libdisplay-info, libliftoff
# and waymote (https://github.com/rockorager/waymote). Update this note with
# the digest.
ARG AMP_WAYLAND_LAYER=sha256:b58c683ff7705c1c59a29d579ff837ed87093da83c33c3a6b7f19fda29e888ff
# Keep with claudeCodeVersion and its checksums in cmd/sbx-worker/claude_code.go:
# sbx-worker uses this copy only when it is that exact build.
ARG CLAUDE_CODE_VERSION=2.1.311
ARG CLAUDE_CODE_SHA256=86dc1fcc69498159eaf15f446613e847010f9036bfbbdffd4c49350be8489ada
# The first release that signs in with the sandbox's workload identity (#15541)
# without `tuist auth login`; SHA-256 of tuist-linux-x86_64.tar.gz from the
# release's SHASUMS256.txt.
ARG TUIST_VERSION=4.220.0-canary.26
ARG TUIST_SHA256=be604c8bc2230226903174e6e433c58ee49f57de223272ec13aeadadda2331e9
# Struo, which thread agents build and test with first; SHA-256 of
# struo-<version>-x86_64-unknown-linux-gnu.tar.gz from the release's .sha256.
ARG STRUO_VERSION=1.0.0
ARG STRUO_SHA256=e6677aa4e086ea3d1c0b70fc06341f4c978c06fd0b2d0aee586aff46be048a33
ARG VERSION=dev
# Ubuntu archive for every apt stage. archive.ubuntu.com and
# security.ubuntu.com served the runner pool at under 1 MB/s for hours, which
# pushed the template build past its timeout; this mirror served it at about
# 74 MB/s. Plain HTTP because the base image has no CA bundle yet; apt
# verifies the archive signatures either way.
ARG UBUNTU_MIRROR=http://mirrors.edge.kernel.org/ubuntu

FROM ubuntu:24.04 AS elixir-toolchain
ARG UBUNTU_MIRROR
RUN sed -i -E "s#https?://(archive|security)\.ubuntu\.com/ubuntu/?#${UBUNTU_MIRROR}/#" /etc/apt/sources.list.d/ubuntu.sources
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl unzip libssl3t64 libncurses6 libtinfo6 \
    && rm -rf /var/lib/apt/lists/*
ARG ERLANG_VERSION=29.1.3
ARG ERLANG_SHA256=1436e790ad4d3d0e8737c3f81010df48460be8bb981b24395ffdb50eb2bdf322
ARG ELIXIR_VERSION=1.20.5
ARG ELIXIR_SHA256=f424d6f0bb710a1d4898f2645d8ad6cab3f5eab8d71848c0dda2579d3a8e8a06
ARG HEX_VERSION=2.7.0
ARG HEX_SHA256=f248381ceb4bef12c990b223a7f998113b1997cb58d29b9883b7d03a0b990f9e
ARG REBAR_VERSION=3.28.0
ARG REBAR_SHA256=4a8bdd1fc845742833988db73012b232a3e9fd048011189ae9e0cecf70bdb7a2
ENV PATH=/opt/elixir/bin:/opt/erlang/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    MIX_HOME=/opt/mix
# Compile Hex and Rebar with this OTP; their old prebuilt BEAMs cannot load on 29.
RUN set -eu; \
    curl -fsSL --retry 3 "https://builds.hex.pm/builds/otp/amd64/ubuntu-24.04/OTP-${ERLANG_VERSION}.tar.gz" -o /tmp/otp.tar.gz; \
    echo "${ERLANG_SHA256}  /tmp/otp.tar.gz" | sha256sum -c -; \
    mkdir -p /opt/erlang /opt/elixir /opt/mix; \
    tar -xzf /tmp/otp.tar.gz --strip-components=1 -C /opt/erlang; \
    /opt/erlang/Install -minimal /opt/erlang; \
    curl -fsSL --retry 3 "https://builds.hex.pm/builds/elixir/v${ELIXIR_VERSION}-otp-${ERLANG_VERSION%%.*}.zip" -o /tmp/elixir.zip; \
    echo "${ELIXIR_SHA256}  /tmp/elixir.zip" | sha256sum -c -; \
    unzip -q /tmp/elixir.zip -d /opt/elixir; \
    curl -fsSL --retry 3 "https://codeload.github.com/hexpm/hex/tar.gz/refs/tags/v${HEX_VERSION}" -o /tmp/hex.tar.gz; \
    echo "${HEX_SHA256}  /tmp/hex.tar.gz" | sha256sum -c -; \
    mkdir /tmp/hex; tar -xzf /tmp/hex.tar.gz --strip-components=1 -C /tmp/hex; \
    (cd /tmp/hex && MIX_ENV=prod mix archive.build -o /tmp/hex.ez); \
    mix archive.install /tmp/hex.ez --force; \
    curl -fsSL --retry 3 "https://codeload.github.com/erlang/rebar3/tar.gz/refs/tags/${REBAR_VERSION}" -o /tmp/rebar.tar.gz; \
    echo "${REBAR_SHA256}  /tmp/rebar.tar.gz" | sha256sum -c -; \
    mkdir /tmp/rebar; tar -xzf /tmp/rebar.tar.gz --strip-components=1 -C /tmp/rebar; \
    (cd /tmp/rebar && ./bootstrap); \
    install -m 0755 /tmp/rebar/rebar3 /opt/mix/rebar3; \
    elixir --version; HEX_OFFLINE=true mix hex.info; /opt/mix/rebar3 version; \
    rm -rf /tmp/otp.tar.gz /tmp/elixir.zip /tmp/hex.ez /tmp/hex.tar.gz /tmp/hex /tmp/rebar.tar.gz /tmp/rebar

FROM --platform=$BUILDPLATFORM golang:1.26.10-alpine3.23 AS builder
# sbx-worker's checkout tests build and export real repositories.
RUN apk add --no-cache git
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

FROM --platform=$BUILDPLATFORM alpine:3.21 AS amp-wayland
RUN apk add --no-cache curl jq tar
ARG AMP_WAYLAND_LAYER
RUN set -eu; \
    registry=us-central1-docker.pkg.dev; repository=amp-prod-0/amp-orb/amp-orb; \
    token=$(curl -fsS --retry 3 "https://$registry/v2/token?scope=repository:$repository:pull&service=$registry" | jq -r .token); \
    curl -fsSL --retry 3 -H "Authorization: Bearer $token" -o /tmp/layer.tgz \
        "https://$registry/v2/$repository/blobs/${AMP_WAYLAND_LAYER}"; \
    echo "${AMP_WAYLAND_LAYER#sha256:}  /tmp/layer.tgz" | sha256sum -c -; \
    mkdir /out && tar -xzf /tmp/layer.tgz -C /out opt/amp-wayland; \
    test -x /out/opt/amp-wayland/bin/labwc; \
    test -x /out/opt/amp-wayland/bin/waymote-gateway; \
    test -x /out/opt/amp-wayland/libexec/waymote-streamd

# Same Ubuntu digest as infra/linux-runner-image's default base, so sandbox
# guests and Linux CI jobs share system libraries and native build caches.
# Renovate bumps both together (see renovate.json).
FROM ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852 AS guest
ENV DEBIAN_FRONTEND=noninteractive
ARG UBUNTU_MIRROR
RUN sed -i -E "s#https?://(archive|security)\.ubuntu\.com/ubuntu/?#${UBUNTU_MIRROR}/#" /etc/apt/sources.list.d/ubuntu.sources
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash coreutils ca-certificates curl wget git git-lfs openssh-client gnupg sudo tzdata locales \
        iproute2 iputils-ping dnsutils procps psmisc less vim-tiny nano jq ripgrep fd-find unzip zip tar \
        xz-utils zstd bzip2 build-essential clang libclang-dev pkg-config cmake python3 python3-pip python3-venv \
        e2fsprogs util-linux lsof strace htop tmux rsync sqlite3 libssl-dev zlib1g-dev libncurses6 libtinfo6 \
        ffmpeg imagemagick \
    && rm -rf /var/lib/apt/lists/*

# No-network actions resolve these root-owned tools through the image binding.
COPY --from=elixir-toolchain /opt/erlang /opt/erlang
COPY --from=elixir-toolchain /opt/elixir /opt/elixir
COPY --from=elixir-toolchain /opt/mix /opt/mix

# Amp Desktop: the packages Amp's custom-image contract lists next to
# /opt/amp-wayland, plus the libraries its labwc links (about 40 MiB). Nothing
# starts at boot: Amp starts the session when the Desktop tab or the agent asks,
# so the template snapshot and an orb that never opens Desktop are unchanged.
# Amp installs Google Chrome on the session's first start.
RUN apt-get update && apt-get install -y --no-install-recommends \
        dbus-x11 fonts-dejavu-core foot gsettings-desktop-schemas libglib2.0-bin \
        libegl1 libgles2 libgtk-3-0t64 libinput10 liblcms2-2 libseat1 libxcb-composite0 \
        libxcb-ewmh2 libxcb-icccm4 libxcb-render0 libxcb-res0 libxcb-xfixes0 libxkbcommon0 \
        libxml2 libnss3-tools pulseaudio swaybg wlr-randr xsettingsd xwayland \
    && rm -rf /var/lib/apt/lists/*
COPY --from=amp-wayland /out/opt/amp-wayland /opt/amp-wayland
RUN export LD_LIBRARY_PATH=/opt/amp-wayland/lib/x86_64-linux-gnu:/opt/amp-wayland/lib \
    && ! ldd /opt/amp-wayland/bin/labwc /opt/amp-wayland/libexec/waymote-streamd | grep "not found" \
    && /opt/amp-wayland/bin/labwc --version

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
# `user` takes UID/GID 1000 from the base image's `ubuntu` account so it owns
# what Linux runner jobs (`runner`, UID 1000) write to caches and checkouts,
# and one custom image's ownership holds on both.
ARG AMP_VERSION
RUN curl -fsSL --retry 3 "https://static.ampcode.com/cli/${AMP_VERSION}/amp-linux-x64" -o /usr/local/bin/amp \
    && curl -fsSL --retry 3 "https://static.ampcode.com/cli/${AMP_VERSION}/linux-x64-amp.sha256" -o /tmp/amp.sha256 \
    && echo "$(cat /tmp/amp.sha256)  /usr/local/bin/amp" | sha256sum -c - \
    && chmod 0755 /usr/local/bin/amp && rm /tmp/amp.sha256 \
    && userdel --remove ubuntu \
    && groupadd --gid 1000 user && useradd --uid 1000 --create-home --gid user --shell /bin/bash user \
    && echo 'user ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/amp-user \
    && chmod 0440 /etc/sudoers.d/amp-user \
    && visudo -cf /etc/sudoers.d/amp-user
COPY --chmod=0755 orb-bootstrap.sh /usr/local/bin/sbx-orb-bootstrap

# Claude Code's self-hosted runner, which sbx-worker runs as `user` for Claude
# Code cloud sessions.
ARG CLAUDE_CODE_VERSION
ARG CLAUDE_CODE_SHA256
RUN curl -fsSL --retry 3 "https://downloads.claude.ai/claude-code-releases/${CLAUDE_CODE_VERSION}/linux-x64/claude" -o /usr/local/bin/claude \
    && echo "${CLAUDE_CODE_SHA256}  /usr/local/bin/claude" | sha256sum -c - \
    && chmod 0755 /usr/local/bin/claude

# Amp's own orb image ships agent-browser the same way: a global npm install,
# then Chrome for Testing and its system libraries installed as `user`, so the
# browser lives in /home/user/.agent-browser where the CLI looks for it.
ARG AGENT_BROWSER_VERSION
RUN npm install -g "agent-browser@${AGENT_BROWSER_VERSION}" \
    && test "$(agent-browser --version)" = "agent-browser ${AGENT_BROWSER_VERSION}" \
    && runuser -u user -- env -i HOME=/home/user USER=user PATH=/usr/local/bin:/usr/bin:/bin \
        bash -c 'cd /home/user && agent-browser install --with-deps' \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /root/.npm

# Agents read the project's Tuist data with no setup: the Tuist CLI, which signs
# in with the sandbox's own identity, and a skill for when to use it. Amp also
# loads skills from ~/.claude/skills. No MCP server is preinstalled: users and
# projects that want Tuist's MCP add it themselves.
ARG TUIST_VERSION
ARG TUIST_SHA256
RUN curl -fsSL --retry 3 -o /tmp/tuist.tar.gz \
        "https://github.com/tuist/tuist/releases/download/${TUIST_VERSION}/tuist-linux-x86_64.tar.gz" \
    && echo "${TUIST_SHA256}  /tmp/tuist.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/tuist.tar.gz -C /usr/local/bin tuist \
    && chown root:root /usr/local/bin/tuist && chmod 0755 /usr/local/bin/tuist && rm /tmp/tuist.tar.gz \
    && test "$(tuist version)" = "${TUIST_VERSION}"
# Struo for builds and tests (`Tuist.Threads.Agent`). It reports a build's
# progress to the file `STRUO_PROGRESS` names, which every sandbox command sets
# (`Tuist.Sandboxes.Commands`). Its binary links libasound for `--sound`.
ARG STRUO_VERSION
ARG STRUO_SHA256
RUN apt-get update && apt-get install -y --no-install-recommends libasound2t64 \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL --retry 3 -o /tmp/struo.tar.gz \
        "https://github.com/tuist/struo/releases/download/${STRUO_VERSION}/struo-${STRUO_VERSION}-x86_64-unknown-linux-gnu.tar.gz" \
    && echo "${STRUO_SHA256}  /tmp/struo.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/struo.tar.gz -C /usr/local/bin struo \
    && chown root:root /usr/local/bin/struo && chmod 0755 /usr/local/bin/struo && rm /tmp/struo.tar.gz \
    && test "$(struo --version)" = "struo ${STRUO_VERSION}"
COPY agent-home/skills/ /home/user/.claude/skills/
RUN chown -R user:user /home/user/.claude

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

# REAPI actions run as `builder` (UID/GID 2000, internal/executor.actionUID):
# it cannot read the root worker's CAS credential or control sockets and,
# unlike `user`, has no sudo.
RUN groupadd --gid 2000 builder && useradd --uid 2000 --gid builder --create-home builder

# The rootfs stage runs natively: mkfs.ext4 -d produces the same image on any
# host, and this keeps the multi-gigabyte populate step off the emulator.
FROM --platform=$BUILDPLATFORM ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852 AS rootfs
ARG UBUNTU_MIRROR
RUN sed -i -E "s#https?://(archive|security)\.ubuntu\.com/ubuntu/?#${UBUNTU_MIRROR}/#" /etc/apt/sources.list.d/ubuntu.sources
RUN apt-get update && apt-get install -y --no-install-recommends e2fsprogs ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
ARG KERNEL_URL
ARG KERNEL_SHA256
RUN mkdir -p /out \
    && curl -fsSL --retry 3 -o /out/vmlinux "${KERNEL_URL}" \
    && curl -fsSL --retry 3 -o /out/vmlinux.config "${KERNEL_URL}.config" \
    && if [ -n "${KERNEL_SHA256}" ]; then echo "${KERNEL_SHA256}  /out/vmlinux" | sha256sum -c -; fi
COPY --from=guest / /rootfs
# /etc/hostname, hosts and resolv.conf are bind mounts inside a build
# container, so their defaults are seeded here where they are plain files.
# sbx-init rewrites all three at boot.
# The filesystem is sized to its contents plus room for ext4's own metadata,
# not to what a guest gets: the image layer carries the file dense, so every
# GiB here would cost every node's image store. install-template.sh grows it
# to ROOTFS_SIZE on the node.
RUN mkdir -p /rootfs/dev /rootfs/proc /rootfs/sys /rootfs/run /rootfs/tmp /rootfs/workspace /rootfs/mnt/memory \
    && rm -f /rootfs/etc/resolv.conf \
    && echo sandbox > /rootfs/etc/hostname \
    && printf '127.0.0.1\tlocalhost\n127.0.1.1\tsandbox\n::1\tlocalhost ip6-localhost ip6-loopback\n' > /rootfs/etc/hosts \
    && used_mib="$(du -sxm /rootfs | cut -f1)" \
    && truncate -s "$((used_mib + used_mib / 4 + 1024))M" /out/rootfs.ext4 \
    && mkfs.ext4 -q -F -L rootfs -d /rootfs -E lazy_itable_init=0,lazy_journal_init=0 /out/rootfs.ext4 \
    && kernel="$(basename "${KERNEL_URL}")" && kernel="${kernel#vmlinux-}" \
    && runner_uid="$(awk -F: '$1 == "user" { print $3 }' /rootfs/etc/passwd)" \
    && runner_gid="$(awk -F: '$1 == "user" { print $4 }' /rootfs/etc/passwd)" \
    && test -n "${runner_uid}" && test -n "${runner_gid}" \
    && printf '{"name":"default","kernel":"%s","built_at":"%s","runner_uid":%s,"runner_gid":%s}\n' \
        "${kernel}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${runner_uid}" "${runner_gid}" > /out/metadata.json \
    && cat /out/metadata.json && ls -la /out && du -h /out/*

# Build with --target execution-gateway for the stateless public REAPI service.
FROM alpine:3.21 AS execution-gateway
RUN apk add --no-cache ca-certificates
COPY --from=builder /out/reapi-gateway /usr/local/bin/reapi-gateway
USER 65534:65534
EXPOSE 50051
ENTRYPOINT ["/usr/local/bin/reapi-gateway"]

# GNU coreutils for cp --sparse=always and truncate (busybox's cp cannot keep
# holes, and a dense copy would cost every node the full rootfs), e2fsck and
# resize2fs to grow the rootfs to ROOTFS_SIZE.
FROM alpine:3.21
RUN apk add --no-cache coreutils e2fsprogs e2fsprogs-extra
COPY --from=rootfs /out /template
COPY install-template.sh /install-template.sh
ENTRYPOINT ["/install-template.sh"]
