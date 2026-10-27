# Noora Storybook Chart

- Keep this standalone release app-only: no server workloads or shared platform controllers.
- Preserve production hardening: no service-account token automount, restricted container privileges, explicit network boundaries.
- Prefer generic Kubernetes values over environment-specific template wiring.
- Run the `helm lint` and production-plus-CI `helm template` commands in [README.md](README.md#local-validation) from the repository root. CI values supply a placeholder image tag.
