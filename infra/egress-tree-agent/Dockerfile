# DaemonSet agent that enforces the per-node shared egress HTB tree for kura
# pods. See AGENTS.md for the architecture and cmd/agent for the entrypoint.
#
# alpine (not distroless): the agent shells out to `ip` and `tc` for device
# and qdisc management. Root user: it attaches tcx BPF programs and writes
# sysctls. The DaemonSet runs it privileged — see the Helm manifest's
# securityContext comment: the container runtime's read-only /proc/sys mask
# breaks the sysctl writes under a capabilities-only NET_ADMIN/BPF grant.
ARG GO_VERSION=1.26.10
ARG ALPINE_VERSION=3.22

# The patched SDK has no alpine3.22 tag. Copy only the toolchain so clang,
# BPF headers, iproute2, and the runtime distribution keep their previous line.
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine3.24@sha256:9ce231b28998b32e116927c61aa5c406183061d4f3f2d61b292c88e7f6bdf7ca AS go-toolchain
FROM --platform=$BUILDPLATFORM alpine:${ALPINE_VERSION} AS builder
ARG GO_VERSION
COPY --from=go-toolchain /usr/local/go /usr/local/go
ENV GOPATH=/go
ENV GOTOOLCHAIN=local
ENV PATH=/usr/local/go/bin:/go/bin:$PATH
RUN test "$(go env GOVERSION)" = "go${GO_VERSION}" && go version

# clang + libbpf headers: the BPF bindings are generated here (bpf2go), not
# committed. The bytecode targets the bpf pseudo-arch, so generating on the
# build platform is correct for every TARGETARCH.
RUN apk add --no-cache clang libbpf-dev linux-headers

WORKDIR /src
COPY infra/egress-tree-agent/go.mod infra/egress-tree-agent/go.sum ./
RUN go mod download

COPY infra/egress-tree-agent ./

ARG TARGETOS
ARG TARGETARCH
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    go generate ./internal/agent && \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" -o /out/agent ./cmd/agent && \
    go version -m /out/agent | grep -F ": go${GO_VERSION}"

FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache iproute2 iproute2-tc 'ca-certificates>=20261020-r0' \
    && update-ca-certificates

COPY --from=builder /out/agent /usr/local/bin/agent

USER 0:0
ENTRYPOINT ["/usr/local/bin/agent"]
