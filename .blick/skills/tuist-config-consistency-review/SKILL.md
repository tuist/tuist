---
name: tuist-config-consistency-review
description: Cross-file configuration consistency checks for infrastructure, deployment, and service configuration files. Flags version mismatches, timeout misalignments, and configuration drift between related files.
---

# Tuist Configuration Consistency Review

This skill checks for consistency between related configuration values
across different files. Mismatches between binary versions and config
formats, proxy/backend timeouts, and other cross-file dependencies often
pass silently until they cause runtime failures.

For each finding, cite both file paths and line numbers, quote the
relevant snippets, and explain the relationship.

---

## 1. Container runtime version vs config format version

Containerd and similar runtimes have config file formats that are
tightly coupled to binary versions. A version mismatch prevents the
runtime from starting.

### Flag (Severity: critical)

- **A workflow or script installs containerd 1.7.x but writes a config
  with `version = 3` or `io.containerd.cri.v1.runtime` plugin paths.**
  Containerd 1.7.x only supports config version 2 and the
  `io.containerd.grpc.v1.cri` plugin path. Containerd 2.x uses version 3
  and the `v1.runtime` path.
- **A bare-metal bootstrap or cloud-init script installs containerd via
  package manager (apt) but hand-writes a config file without using
  `containerd config default` from the installed binary.**

### Do not flag

- Configurations that use `containerd config default` to generate the base
  config before appending custom sections — this ensures the config
  matches the installed binary.
- Installations that explicitly install containerd 2.x from upstream tarballs
  when using version 3 configs.

---

## 2. Proxy/backend timeout alignment

When a reverse proxy (nginx, envoy) sits in front of an application
server, the proxy's timeout should be slightly longer than the server's
timeout to avoid premature connection closures.

### Flag (Severity: medium)

- **A Helm values file or nginx config sets a `proxy_read_timeout` or
  similar that is less than or equal to an application server's read
  timeout** configured in `config/runtime.exs` or similar.
  
  Example problematic pattern:
  ```yaml
  # infra/helm/platform/values.yaml
  nginx-ingress:
    controller:
      config:
        proxy-read-timeout: "10"  # seconds
  ```
  
  ```elixir
  # server/config/runtime.exs
  thousand_island_options: [
    read_timeout: to_timeout(second: 15)  # longer than proxy timeout
  ]
  ```
  
  The proxy will timeout before the server, causing 502/504 errors.

### Do not flag

- Timeouts that are clearly documented as intentional (e.g., a short
  client-facing timeout with a longer backend processing timeout).
- Cases where the proxy timeout is at least 20% longer than the backend
  timeout (healthy gap for network latency).

---

## 3. CRD schema vs template value compatibility

Kubernetes CRDs declared with strict schemas (without
`x-kubernetes-preserve-unknown-fields: true`) will prune fields that
aren't in the OpenAPI schema. Templates that render undefined fields
produce silent dead code.

### Flag (Severity: medium)

- **A Helm template renders a field (e.g., `autoscaling.machineDeployment`)
  that doesn't exist in the CRD's OpenAPI schema** and the CRD doesn't
  have `x-kubernetes-preserve-unknown-fields: true` on that path.
- **A Go struct has JSON tags for fields not present in the CRD type**
  when the CRD uses strict validation.

### Do not flag

- CRDs that explicitly set `x-kubernetes-preserve-unknown-fields: true`
  on the path where the field is rendered.
- Fields that are conditionally rendered based on a feature flag that
  correlates with a CRD version that does include the field.

---

## 4. Secret/token lifetime alignment

Short-lived tokens issued by one system should be valid long enough to
reach the consuming system, accounting for clock skew and retries.

### Flag (Severity: medium)

- **A workflow issues a token with a TTL shorter than the expected
duration of the job that uses it**, especially when the token is
generated early in a multi-step workflow.
- **A Kubernetes ServiceAccount token projected into a Pod has a
  shorter expiration than the longest expected Pod runtime** without
  renewal logic.

### Do not flag

- Tokens that are explicitly refreshed or rotated during the workflow.
- Cases where the short TTL is intentional for security with clear
  documentation about the constraint.

---

## Out of scope (handled elsewhere — do not flag)

- YAML formatting, indentation, or style issues → handled by YAML
  linters and `helm lint`.
- Missing or extra keys in configs unless they cause a cross-file
  consistency issue as described above.
- Version updates that only touch a single file (e.g., bumping a Docker
  image tag without a coupled config change).

## Before submitting findings

For each finding, confirm:

1. Both file paths and line numbers are real and the snippets appear in
the PR diff.
2. The relationship between the values is correctly explained.
3. The severity is appropriate: **critical** for runtime failures
(containerd version mismatch), **medium** for operational issues
(timeout misalignment, dead code).
4. The finding isn't about a single-file issue unless it creates a
future cross-file consistency risk.