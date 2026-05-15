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

# Baseline tooling. The runner binary itself needs libicu70 + libssl3
# + libkrb5; the rest is the minimum a typical CI workflow expects
# to find on Ubuntu (git, build tools, archivers, curl, jq).
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
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Non-root runner user. `actions/runner` refuses to register as
# root unless `RUNNER_ALLOW_RUNASROOT=1` is set — explicitly opt
# out by creating a dedicated user. The user gets passwordless
# sudo so workflow steps can install packages without prompting,
# matching the GitHub-hosted runner experience.
RUN useradd -m -d /home/runner -s /bin/bash runner \
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
COPY dispatch-poll.sh /usr/local/bin/dispatch-poll.sh
RUN chmod +x /usr/local/bin/dispatch-poll.sh

USER runner

# PID 1 is the polling script. It exec's the runner once a JIT
# config lands, and exits normally when `./run.sh` returns.
CMD ["/usr/local/bin/dispatch-poll.sh"]
