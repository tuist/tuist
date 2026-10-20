# syntax=docker/dockerfile:1
ARG TARGETARCH
FROM alpine:3.22 AS binaries-amd64
ADD --checksum=sha256:7c5bd8512c6e966455b1d198209358b2d191c77a83ab377c4073281065fb855f https://github.com/minio/minio/releases/download/RELEASE.2025-09-07T16-13-09Z/minio.linux-amd64.RELEASE.2025-09-07T16-13-09Z /usr/local/bin/minio
ADD --checksum=sha256:01f866e9c5f9b87c2b09116fa5d7c06695b106242d829a8bb32990c00312e891 https://github.com/minio/mc/releases/download/RELEASE.2025-08-13T08-35-41Z/mc.linux-amd64.RELEASE.2025-08-13T08-35-41Z /usr/local/bin/mc

FROM alpine:3.22 AS binaries-arm64
ADD --checksum=sha256:5c83cd2cf151717ba0243f73e1c7802ff36e272b67144bdd7f1f7d684fd6f03d https://github.com/minio/minio/releases/download/RELEASE.2025-09-07T16-13-09Z/minio.linux-arm64.RELEASE.2025-09-07T16-13-09Z /usr/local/bin/minio
ADD --checksum=sha256:14c8c9616cfce4636add161304353244e8de383b2e2752c0e9dad01d4c27c12c https://github.com/minio/mc/releases/download/RELEASE.2025-08-13T08-35-41Z/mc.linux-arm64.RELEASE.2025-08-13T08-35-41Z /usr/local/bin/mc

FROM binaries-${TARGETARCH}
RUN chmod +x /usr/local/bin/minio /usr/local/bin/mc
ENTRYPOINT ["minio"]
