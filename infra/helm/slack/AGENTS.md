# Slack Chart

- Keep this standalone release app-only: no server workloads or shared platform controllers.
- Preserve production hardening: no service-account token automount, restricted container privileges, explicit ingress/egress boundaries.
- SQLite uses one PVC: keep a single replica and `Recreate` strategy, not overlapping rolling-update Pods.
- Run the `helm lint` and production-plus-CI `helm template` commands in [README.md](README.md#validation) from the repository root. Use CI placeholder secrets, not real credentials.
