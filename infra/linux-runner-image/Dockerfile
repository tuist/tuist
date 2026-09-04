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

ARG GO_VERSION=1.25

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-bookworm AS runner-shell-agent-builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY cmd ./cmd
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    go test ./...

ARG TARGETOS=linux
ARG TARGETARCH=amd64
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" -o /out/runner-shell-agent ./cmd/runner-shell-agent

# Android SDK resolver. sdkmanager is a JVM tool, so it runs here in a
# JDK stage and only the resolved SDK is copied into the final image —
# workflow steps bring their own JDK via mise, so the runner image
# itself stays JDK-free.
#
# Platforms and build-tools are selected by a version FLOOR, not pinned:
# every release at or above it that Google publishes gets installed. This
# image runs customer workflows, so it cannot assume anyone's compileSdk
# — a customer on a newer platform than we happened to pin would fail at
# Gradle configuration exactly like a missing SDK. GitHub's hosted image
# takes the same approach (`platform_min_version` / `build_tools_min_version`
# in its toolset), which also means new platforms roll in on the next
# image rebuild with no version bump anywhere.
#
# The cmdline-tools archive is fetched straight from Google because
# sdkmanager is what installs every other component (it cannot install
# itself), and is held at the release GitHub's hosted image pins.
# sdkmanager stamps a schema version into each installed package's
# package.xml, and current cmdline-tools writes v4 while AGP 8.7 parses
# only up to v3 — which makes every Gradle invocation warn about the
# skew. Keep it behind the AGP releases customers are likely to run.
FROM eclipse-temurin:21-jdk-jammy AS android-sdk

ARG ANDROID_CMDLINE_TOOLS_ARCHIVE=commandlinetools-linux-11076708_latest.zip
ARG ANDROID_PLATFORM_MIN_VERSION=34
ARG ANDROID_BUILD_TOOLS_MIN_VERSION=34

ENV ANDROID_SDK_ROOT=/opt/android-sdk

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools" \
    && curl -fSL "https://dl.google.com/android/repository/${ANDROID_CMDLINE_TOOLS_ARCHIVE}" \
         -o /tmp/cmdline-tools.zip \
    && unzip -qq /tmp/cmdline-tools.zip -d "${ANDROID_SDK_ROOT}/cmdline-tools" \
    && rm /tmp/cmdline-tools.zip \
    # sdkmanager only resolves ANDROID_SDK_ROOT when it sits at
    # cmdline-tools/latest; the archive unpacks to cmdline-tools/.
    && mv "${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools" "${ANDROID_SDK_ROOT}/cmdline-tools/latest" \
    # Licenses are accepted at build time. Without the hashes under
    # $ANDROID_SDK_ROOT/licenses, Gradle refuses the platform at
    # configuration time the same way a missing SDK does.
    && yes | "${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" --licenses > /dev/null \
    # Enumerate what Google currently publishes and keep everything at or
    # above the floor, rather than hardcoding a list that silently rots.
    # `rc` build-tools are excluded the way the hosted image excludes them.
    # Take package ids from the first column of the "Available Packages"
    # table rather than grepping the raw text: ids are matched whole, so
    # preview channels (android-37.2-beta1, build-tools;36.0.0-rc1) drop
    # out instead of being truncated into ids that do not exist. Platform
    # ids carry an optional minor (android-37.0) and an optional extension
    # suffix (android-36-ext18); both are real, separate packages.
    && available="$("${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" --list \
         | sed -n '/Available Packages:/,$p' | cut -d'|' -f1 | tr -d ' ' | sort -u)" \
    && platforms="$(echo "$available" | grep -E '^platforms;android-[0-9]+(\.[0-9]+)?(-ext[0-9]+)?$' \
         | awk -F'android-' -v min="${ANDROID_PLATFORM_MIN_VERSION}" '{ split($2, v, "-"); if (v[1] + 0 >= min + 0) print $0 }')" \
    && build_tools="$(echo "$available" | grep -E '^build-tools;[0-9]+\.[0-9]+\.[0-9]+$' \
         | awk -F'build-tools;' -v min="${ANDROID_BUILD_TOOLS_MIN_VERSION}" '{ split($2, v, "."); if (v[1] + 0 >= min + 0) print $0 }')" \
    && test -n "$platforms" && test -n "$build_tools" \
    && echo "Installing platforms:" $platforms \
    && echo "Installing build-tools:" $build_tools \
    && "${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" \
         "platform-tools" \
         $platforms \
         $build_tools \
    # World-writable, matching the hosted image: AGP writes into the SDK
    # root (temp dirs, package installs) and the workflow runs as
    # `runner`, not root.
    && chmod -R a+rwX "${ANDROID_SDK_ROOT}"

FROM ubuntu:22.04

# renovate: datasource=github-releases depName=actions/runner
ARG RUNNER_VERSION=2.336.0
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

# kubectl + helm + gh: GitHub's Ubuntu runner image pre-installs all
# three (kubectl/helm via `install-kubernetes-tools.sh`, gh via
# `install-github-cli.sh`), so workflow steps assume they're on
# `/usr/local/bin` — k8s deploy / sweep jobs reach for kubectl/helm,
# and jobs that dispatch workflows or comment on PRs reach for gh.
# Mirror that posture here. Versions are Renovate-managed; bumps
# land as `fix(linux-runner-image): …` and route through the
# release flow same as `RUNNER_VERSION`.
# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION=1.36.1
# renovate: datasource=github-releases depName=helm/helm
ARG HELM_VERSION=4.2.0
# renovate: datasource=github-releases depName=cli/cli
ARG GH_VERSION=2.97.0
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
    && helm version --short \
    && curl -fSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" \
         -o /tmp/gh.tgz \
    && tar -xzf /tmp/gh.tgz -C /tmp \
    && mv "/tmp/gh_${GH_VERSION}_linux_${ARCH}/bin/gh" /usr/local/bin/gh \
    && rm -rf /tmp/gh.tgz "/tmp/gh_${GH_VERSION}_linux_${ARCH}" \
    && chmod 0755 /usr/local/bin/gh \
    && gh --version

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

# Android SDK, resolved in the `android-sdk` stage above. Gradle
# cannot configure an Android project without a platform + build-tools:
# it fails the task graph with "SDK location not found" before any task
# runs. GitHub's hosted Ubuntu image bakes the SDK in the same way
# (`install-android-sdk.sh`, exporting ANDROID_HOME + ANDROID_SDK_ROOT),
# so workflows assume it is on the machine rather than installing it
# per job — and the path below matches theirs for workflows that
# hardcode it.
#
# Deliberately narrower than the hosted image, which carries every
# platform from android-34 up, six build-tools releases and three NDK
# majors. We ship the single platform + build-tools pair `android/`
# builds against and no NDK at all (the app has no native code), which
# is what keeps this a few hundred MB rather than the ~10GB the hosted
# image spends here.
COPY --from=android-sdk /opt/android-sdk /usr/local/lib/android/sdk
# The copied tree keeps the modes set in the builder stage, but COPY
# creates the destination directory itself as 0755, so the SDK root
# alone would be read-only for `runner`. Re-chmod just that directory —
# a recursive chmod here would rewrite every file into a second ~460MB
# layer.
RUN chmod a+rwx /usr/local/lib/android/sdk
ENV ANDROID_HOME=/usr/local/lib/android/sdk \
    ANDROID_SDK_ROOT=/usr/local/lib/android/sdk

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

# The Buildkite agent lives alongside the GitHub one rather than in a
# second image. Which of the two runs is a per-job decision the server
# makes at dispatch, so a Pod has to be able to serve either; forking the
# image would split the warm pool to save one binary.
#
# Pinned for the same reason RUNNER_VERSION is: the version that ran a
# job should be the version we baked. The agent has no self-update, so
# pinning here is the whole mechanism. Renovate bumps it the same way.
# renovate: datasource=github-releases depName=buildkite/agent
ARG BUILDKITE_AGENT_VERSION=3.87.0
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) bk_arch=amd64 ;; \
      arm64) bk_arch=arm64 ;; \
      *) echo "unsupported architecture" >&2; exit 1 ;; \
    esac; \
    curl -fSL "https://github.com/buildkite/agent/releases/download/v${BUILDKITE_AGENT_VERSION}/buildkite-agent-linux-${bk_arch}-${BUILDKITE_AGENT_VERSION}.tar.gz" \
        -o /tmp/buildkite-agent.tar.gz; \
    mkdir -p /tmp/buildkite-agent-dist; \
    tar xzf /tmp/buildkite-agent.tar.gz -C /tmp/buildkite-agent-dist; \
    install -m 0755 /tmp/buildkite-agent-dist/buildkite-agent /usr/local/bin/buildkite-agent; \
    rm -rf /tmp/buildkite-agent.tar.gz /tmp/buildkite-agent-dist; \
    buildkite-agent --version

# Global agent hooks (`--hooks-path`), so they run for every job
# regardless of what the customer's repository defines. `environment`
# re-exports the cache settings the server sent; `pre-exit` posts the
# job's log and window back, authenticating with the job-scoped report
# token the poller staged — never the SA token, which this container
# does not hold.
COPY buildkite-hooks/ /usr/local/share/tuist/buildkite-hooks/
RUN chmod +x /usr/local/share/tuist/buildkite-hooks/*

# dispatch-poll.sh runs in the `poller` init container (holds the SA
# token, stages the JIT); run-job.sh runs in the `runner` main
# container (no token, runs the staged JIT). The controller's
# podtemplate wires which container runs which. See
# infra/runners-controller/AGENTS.md for the split-credential shape.
COPY dispatch-poll.sh /usr/local/bin/dispatch-poll.sh
COPY run-job.sh /usr/local/bin/run-job.sh
COPY vitals.sh /usr/local/bin/vitals.sh
COPY --from=runner-shell-agent-builder /out/runner-shell-agent /usr/local/bin/runner-shell-agent
# metrics-sampler.sh runs in the `metrics` native-sidecar container
# (holds the SA token like the poller; never the runner container) and
# POSTs the microVM's machine metrics for the job detail page.
COPY metrics-sampler.sh /usr/local/bin/metrics-sampler.sh
RUN chmod +x /usr/local/bin/dispatch-poll.sh /usr/local/bin/run-job.sh /usr/local/bin/vitals.sh /usr/local/bin/runner-shell-agent /usr/local/bin/metrics-sampler.sh

USER runner

# Default CMD is the poll loop, used by the poller init container.
# The runner main container overrides this with run-job.sh via the
# controller's podtemplate. On a single-container (non-split)
# deployment dispatch-poll.sh execs the runner itself.
CMD ["/usr/local/bin/dispatch-poll.sh"]
