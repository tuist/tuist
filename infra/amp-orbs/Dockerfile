# The controller is independent of the guest: it needs no KVM or cluster API access.
FROM ubuntu:24.04
ARG AMP_VERSION=0.0.1793104576-gc52692
ARG AMP_SHA256=fdc30a88aeca5aad920ee32af6e87c9875e5e055497911183ed0265f49a53fa0
ARG TUIST_VERSION=4.216.0-canary.10
ARG TUIST_SHA256=45821735480ee54d5fba4d39f9d5c63c5589ff9a898090d8c4e24a4a7b1a324c
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl jq coreutils util-linux tini libstdc++6 \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL --retry 3 "https://static.ampcode.com/cli/${AMP_VERSION}/amp-linux-x64" -o /usr/local/bin/amp \
    && echo "$AMP_SHA256  /usr/local/bin/amp" | sha256sum -c - \
    && chmod 0755 /usr/local/bin/amp \
    && curl -fsSL --retry 3 "https://github.com/tuist/tuist/releases/download/${TUIST_VERSION}/tuist-linux-x86_64.tar.gz" -o /tmp/tuist.tar.gz \
    && echo "$TUIST_SHA256  /tmp/tuist.tar.gz" | sha256sum -c - \
    && mkdir -p /opt/tuist && tar -xzf /tmp/tuist.tar.gz -C /opt/tuist \
    && ln -s /opt/tuist/tuist /usr/local/bin/tuist && rm /tmp/tuist.tar.gz
RUN useradd --uid 10001 --home-dir /state --create-home provider
COPY --chmod=755 dispatch.sh run-provider.sh /opt/tuist-amp-orbs/
USER 10001:10001
ENV HOME=/state XDG_CONFIG_HOME=/state/config XDG_STATE_HOME=/state/data XDG_CACHE_HOME=/state/cache TUIST_CONFIG_STATS_OPT_OUT=true
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/opt/tuist-amp-orbs/run-provider.sh"]
