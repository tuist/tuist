# DaemonSet agent that enforces the per-node shared egress HTB tree for kura
# pods. See AGENTS.md for the architecture and cmd/agent for the entrypoint.
#
# alpine (not distroless): the agent shells out to `ip` and `tc` for device
# and qdisc management. Root user: it attaches tcx BPF programs and writes
# sysctls (the pod grants NET_ADMIN/BPF, not full privilege).
ARG GO_VERSION=1.25
ARG ALPINE_VERSION=3.22

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS builder

WORKDIR /src
COPY infra/egress-tree-agent/go.mod infra/egress-tree-agent/go.sum ./
RUN go mod download

COPY infra/egress-tree-agent ./

ARG TARGETOS
ARG TARGETARCH
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 \
    go build -trimpath -ldflags="-s -w" -o /out/agent ./cmd/agent

FROM alpine:${ALPINE_VERSION}

RUN apk add --no-cache iproute2 iproute2-tc

COPY --from=builder /out/agent /usr/local/bin/agent

USER 0:0
ENTRYPOINT ["/usr/local/bin/agent"]
