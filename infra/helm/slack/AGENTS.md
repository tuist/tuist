# Slack Helm Chart

## Overview

Standalone Helm chart for the public Slack invitation app deployment. This
chart owns the `slack.tuist.dev` release boundary and is deployed
independently from the main Tuist server chart.

## Scope

- Slack invitation app `Deployment`, `Service`, `Ingress`, and runtime `Secret`
- SQLite `PersistentVolumeClaim`
- Optional `ExternalSecret` wiring for managed-cluster runtime credentials
- App `ServiceAccount` and namespace-scoped `NetworkPolicy`
- Production overlay values for the managed cluster
- Release-specific validation and operational documentation

## Conventions

- Keep this chart focused on the Slack invitation app only. Do not add Tuist
  server workloads or shared platform controllers here.
- Assume shared-cluster deployment and keep the production overlay hardened by
  default: no service-account token mount, restricted container privileges, and
  explicit ingress / egress boundaries.
- Because the app uses a single SQLite database file, prefer a single replica
  with a `Recreate` rollout strategy over rolling two pods against one PVC.
- Validate with `helm lint` and `helm template` using placeholder runtime
  secrets from `values-ci.yaml`.

## Local Validation

```bash
helm lint infra/helm/slack \
  -f infra/helm/slack/values-ci.yaml
helm template slack infra/helm/slack \
  -f infra/helm/slack/values-production.yaml \
  -f infra/helm/slack/values-ci.yaml
```
