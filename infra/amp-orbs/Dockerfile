# The controller is independent of the guest: it needs no KVM or cluster API access.
FROM ubuntu:24.04
ARG AMP_VERSION=0.0.1793868001-g0e9889
ARG AMP_SHA256=f945e79dde17eeaf7304fa564a5f0ff86c37419e879b420d8ba6f73ad3a98911
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl jq coreutils util-linux tini libstdc++6 \
    && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL --retry 3 "https://static.ampcode.com/cli/${AMP_VERSION}/amp-linux-x64" -o /usr/local/bin/amp \
    && echo "$AMP_SHA256  /usr/local/bin/amp" | sha256sum -c - \
    && chmod 0755 /usr/local/bin/amp
RUN useradd --uid 10001 --home-dir /state --create-home provider
COPY --chmod=755 dispatch.sh run-provider.sh /opt/tuist-amp-orbs/
USER 10001:10001
ENV HOME=/state XDG_CONFIG_HOME=/state/config XDG_STATE_HOME=/state/data XDG_CACHE_HOME=/state/cache TUIST_CONFIG_STATS_OPT_OUT=true
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/opt/tuist-amp-orbs/run-provider.sh"]
