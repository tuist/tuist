# Init container that installs the per-pod egress ceiling qdisc inside the
# pod's network namespace. See AGENTS.md for why this exists and entrypoint.sh
# for the tc program it installs.
#
# alpine (not busybox): busybox tc lacks htb support.
FROM alpine:3.22

RUN apk add --no-cache iproute2-tc

COPY infra/egress-qdisc-init/entrypoint.sh /entrypoint.sh

USER 0:0
ENTRYPOINT ["/entrypoint.sh"]
