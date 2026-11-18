# Luft Web Chart

- Keep this release isolated from the Tuist product: no server workloads, shared secrets, `tuist.dev` hosts, or egress. Luft's web edge calls servers from the browser, never from the pod.
- Caching is decided by the origin's `Cache-Control` in `luft/web/nginx.conf`; keep the table in [README.md](README.md#edge-and-caching) in step with it.
- Run the `helm lint` and production-plus-CI `helm template` commands in [README.md](README.md#local-validation) from the repository root.
