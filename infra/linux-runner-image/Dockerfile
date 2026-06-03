# syntax=docker/dockerfile:1.7

# Tuist Linux runner image — Ubuntu 22.04 base with the GitHub
# Actions runner binary and Tuist's dispatch-poll script baked in.
# Designed to run as a single-job Pod on Hetzner Cloud nodes
# managed by the runners-controller. After `./run.sh --jitconfig
# <config>` exits, the container exits and the Pod's controller
# reaps it; a replacement Pod is created on the next reconcile.
#
# This file is the Linux analog of `infra/runner-image/runner.pkr.hcl`
# (the Tart-based macOS image). The Linux side is dramatically
# simpler because we don't need a VM substrate — containers do the
# isolation, kubelet projects the SA token at a standard path, no
# launchd or tart-kubelet env-share dance.
#
# Renovate auto-bumps RUNNER_VERSION via `renovate.json` config
# matching the same pattern as the macOS image.

# Build the log shipper (streams the runner's stdout to the server's
# log ingest endpoint) from the shared Go module. This stage reaches
# `runner-log-tee/` a level up, so the Docker build context must be
# `infra/` with `-f linux-runner-image/Dockerfile` — see AGENTS.md and
# .github/workflows/linux-runner-image.yml.
FROM golang:1.25 AS tee-builder
WORKDIR /src
COPY runner-log-tee/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -o /out/tuist-log-tee .

FROM ubuntu:22.04

# renovate: datasource=github-releases depName=actions/runner
ARG RUNNER_VERSION=2.334.0
ARG RUNNER_ARCH=x64

# Set runtime defaults so customer workflows see UTF-8 locales out
# of the box and apt-driven installs in workflow steps don't trip
# on interactive prompts.
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    RUNNER_ALLOW_RUNASROOT=0

# Tooling layer. Closes most of the gap against GitHub's
# Ubuntu hosted-runner image without going to the multi-language
# multi-version-toolchain extreme (see PR description for what
# stays deferred to a `tuist-linux-runner-fat` variant).
#
# Categorized for readability:
#   - actions/runner runtime: libicu70 + libssl3 + libkrb5
#   - baseline shell + transfer: bash, ca-certificates, curl, wget,
#     gnupg, jq, locales, lsb-release, sudo, tar, unzip, xz-utils
#   - build toolchain: build-essential pulls gcc/g++/make/libc6-dev;
#     autoconf/automake/libtool/pkg-config/cmake/ninja/m4/bison/flex/
#     gettext cover the long tail of NIF + extension builds
#     (bcrypt_elixir, native Python wheels, native gems, etc.)
#   - dev headers: -dev packages most native modules link against
#     when actions/setup-{node,python,ruby,...} compiles them
#   - archive: zip + bzip2 + p7zip-full (unzip + xz-utils already
#     covered above)
#   - VCS extras: git-lfs (assumed present by many CI workflows),
#     openssh-client for ssh-agent / scp / git-over-ssh (required by
#     webfactory/ssh-agent and any workflow step that talks SSH)
#   - DB clients: client-only — services land in containers in
#     workflows that need them
#   - common CLI utilities: ripgrep, fd-find, tree, less, vim,
#     httpie, netcat, dnsutils, iputils-ping, file
#   - python3 toolchain: python3 + pip + venv so actions/setup-*
#     can bootstrap pip-based tooling without re-installing the
#     interpreter
#
# `actions/runner` registers under a non-root user by default —
# `RUNNER_ALLOW_RUNASROOT=0` enforces it, and the explicit `runner`
# user is created below.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        gnupg \
        jq \
        libicu70 \
        libkrb5-3 \
        libssl3 \
        locales \
        lsb-release \
        sudo \
        tar \
        unzip \
        wget \
        xz-utils \
        build-essential \
        autoconf \
        automake \
        libtool \
        pkg-config \
        cmake \
        ninja-build \
        m4 \
        bison \
        flex \
        gettext \
        libssl-dev \
        libffi-dev \
        zlib1g-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        libncurses-dev \
        libxml2-dev \
        libxslt1-dev \
        libyaml-dev \
        libcurl4-openssl-dev \
        uuid-dev \
        zip \
        bzip2 \
        p7zip-full \
        file \
        git-lfs \
        openssh-client \
        postgresql-client \
        mariadb-client \
        redis-tools \
        sqlite3 \
        ripgrep \
        fd-find \
        tree \
        less \
        vim-tiny \
        httpie \
        netcat-openbsd \
        dnsutils \
        iputils-ping \
        python3 \
        python3-pip \
        python3-venv \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# kubectl + helm: GitHub's Ubuntu runner image pre-installs both
# via `install-kubernetes-tools.sh` so every k8s deploy / sweep
# workflow in the repo assumes they're on `/usr/local/bin`.
# Mirror that posture here. Versions are Renovate-managed; bumps
# land as `fix(linux-runner-image): …` and route through the
# release flow same as `RUNNER_VERSION`.
# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION=1.36.1
# renovate: datasource=github-releases depName=helm/helm
ARG HELM_VERSION=4.2.0
RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" \
         -o /usr/local/bin/kubectl \
    && chmod 0755 /usr/local/bin/kubectl \
    && kubectl version --client \
    && curl -fSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz" \
         -o /tmp/helm.tgz \
    && tar -xzf /tmp/helm.tgz -C /tmp \
    && mv "/tmp/linux-${ARCH}/helm" /usr/local/bin/helm \
    && rm -rf /tmp/helm.tgz "/tmp/linux-${ARCH}" \
    && chmod 0755 /usr/local/bin/helm \
    && helm version --short

# Docker CLI + buildx + compose plugins. The daemon runs in the
# `dind` native sidecar (`docker:dind`); this image carries only
# the client side. `docker-buildx-plugin` isn't in Ubuntu's repos
# and `docker.io` lags upstream, so we use download.docker.com.
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && . /etc/os-release \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-ce-cli \
        docker-buildx-plugin \
        docker-compose-plugin \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Non-root runner user. `actions/runner` refuses to register as
# root unless `RUNNER_ALLOW_RUNASROOT=1` is set. Passwordless sudo
# matches the hosted-runner experience. The `docker` group GID is
# pinned to 123 to match the `--group=123` arg the controller
# passes to dockerd in the sidecar, so the runner can reach
# /var/run/docker.sock without sudo.
RUN groupadd -g 123 docker \
    && useradd -m -d /home/runner -s /bin/bash -G docker runner \
    && echo "runner ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers \
    && mkdir -p /home/runner/actions-runner \
    && chown -R runner:runner /home/runner

USER runner
WORKDIR /home/runner/actions-runner

# Download + extract the actions/runner tarball. Sha checksum is
# published by GitHub at the release URL; if the bump ever
# desyncs we'll see a `tar: invalid magic` failure here rather
# than a silent mis-install.
RUN curl -fSL "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" \
        -o /tmp/actions-runner.tar.gz \
    && tar xzf /tmp/actions-runner.tar.gz \
    && rm /tmp/actions-runner.tar.gz

USER root
COPY linux-runner-image/dispatch-poll.sh /usr/local/bin/dispatch-poll.sh
COPY --from=tee-builder /out/tuist-log-tee /usr/local/bin/tuist-log-tee
RUN chmod +x /usr/local/bin/dispatch-poll.sh /usr/local/bin/tuist-log-tee

USER runner

# PID 1 is the polling script. It exec's the runner once a JIT
# config lands, and exits normally when `./run.sh` returns.
CMD ["/usr/local/bin/dispatch-poll.sh"]
