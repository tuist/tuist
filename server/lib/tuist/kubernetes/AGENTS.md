# Kubernetes

Minimal Kubernetes API helpers used by Tuist server workloads.

## Guardrails

- Prefer the in-cluster ServiceAccount identity over kubeconfig files.
- Keep kubeconfig-backed helpers scoped to cross-cluster and local-controller use. Production code for the server's own cluster should use the in-cluster client path.
- Keep helpers narrowly scoped to the resources the server owns. Product workload reconciliation belongs in dedicated controllers.
- Return tagged tuples for API failures so callers can decide whether to retry, fail, or ignore `:not_found`.
