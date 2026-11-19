# Test image for the patched nginx: builds nginx from the fork's version and
# patch stack (ours included) with AddressSanitizer (build-nginx.sh), then runs
# the pinned nginx-tests suite plus our *.t files (run.sh).
# Adapted from chainguard-forks/ingress-nginx images/nginx/tests/Dockerfile
# (commit 29e7c87140a9d88ffd3cf26ff07852bb81dc0a4a, Apache-2.0).
#
# Build context: the fork's images/nginx after source.sh; this directory is
# the named context "harness". ../nginx-tests.sh builds and runs it.

# glibc base: AddressSanitizer does not support musl.
FROM ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852

# libpcre3: the fork's nginx build links PCRE1, not PCRE2.
# The Perl modules and memcached are what the suite needs to run its SSL,
# HTTP/3, FastCGI, memcached and WebSocket tests instead of skipping them.
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    libcache-memcached-fast-perl \
    libcache-memcached-perl \
    libcryptx-perl \
    libfcgi-perl \
    libio-socket-ssl-perl \
    libnet-ssleay-perl \
    libpcre3-dev \
    libprotocol-websocket-perl \
    libssl-dev \
    memcached \
    openssl \
    patch \
    perl \
    zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

# Check for recent changes: https://github.com/nginx/nginx-tests/compare/16964ee752509eb6271c4e8760e7899274240755...master
ARG NGINX_TESTS_COMMIT=16964ee752509eb6271c4e8760e7899274240755
ARG NGINX_TESTS_SHA256=b8c445ac5f9134b0e6798624e619fd92558bfa9280a2b84c4b42e5c83e922dc8

RUN curl -fsSL -o /tmp/nginx-tests.tar.gz \
    "https://github.com/nginx/nginx-tests/archive/${NGINX_TESTS_COMMIT}.tar.gz" \
  && echo "${NGINX_TESTS_SHA256}  /tmp/nginx-tests.tar.gz" | sha256sum -c - \
  && mkdir -p /opt/nginx-tests \
  && tar -xzf /tmp/nginx-tests.tar.gz -C /opt/nginx-tests --strip-components=1 \
  && rm /tmp/nginx-tests.tar.gz

COPY --from=harness nginx-tests-no-root.patch /src/tests/
RUN patch -d /opt/nginx-tests -p1 < /src/tests/nginx-tests-no-root.patch

COPY rootfs/version.sh rootfs/download.sh rootfs/build.sh /src/rootfs/
COPY rootfs/patches /src/rootfs/patches
COPY --from=harness build-nginx.sh /src/tests/
RUN bash /src/tests/build-nginx.sh

COPY --from=harness . /src/tests/

RUN useradd --create-home tester
USER tester

ENTRYPOINT ["/src/tests/run.sh"]
