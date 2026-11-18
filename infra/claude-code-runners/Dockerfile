# Runs one Claude Code self-hosted environment's on-demand orchestrator. It
# needs no KVM or cluster API access: its spawn-runner hook hands each work
# order to Tuist, which boots the session's sandbox.
FROM ubuntu:24.04
# Keep with claudeCodeVersion in infra/sandbox-image/cmd/sbx-worker/claude_code.go.
ARG CLAUDE_CODE_VERSION=2.1.311
ARG CLAUDE_CODE_SHA256=86dc1fcc69498159eaf15f446613e847010f9036bfbbdffd4c49350be8489ada
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl jq coreutils tini \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL --retry 3 "https://downloads.claude.ai/claude-code-releases/${CLAUDE_CODE_VERSION}/linux-x64/claude" -o /usr/local/bin/claude \
    && echo "${CLAUDE_CODE_SHA256}  /usr/local/bin/claude" | sha256sum -c - \
    && chmod 0755 /usr/local/bin/claude
RUN useradd --uid 10001 --home-dir /state --create-home provider
COPY --chmod=755 run-orchestrator.sh /opt/tuist-claude-code/
COPY --chmod=755 hooks/spawn-runner /opt/tuist-claude-code/hooks/
USER 10001:10001
ENV HOME=/state XDG_CONFIG_HOME=/state/config XDG_STATE_HOME=/state/data XDG_CACHE_HOME=/state/cache
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/opt/tuist-claude-code/run-orchestrator.sh"]
