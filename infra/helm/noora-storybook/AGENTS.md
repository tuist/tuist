# Noora Storybook Helm Chart

## Overview

Standalone Helm chart for the public Noora Storybook deployment. This chart owns the
`storybook.noora.tuist.dev` release boundary and is deployed independently from the
main Tuist server chart.

## Scope

- Storybook `Deployment`, `Service`, `Ingress`, and runtime `Secret`
- Production overlay values for the managed cluster
- Release-specific validation and operational documentation

## Conventions

- Keep this chart focused on the Storybook app only. Do not add Tuist server workloads
  or shared platform controllers here.
- Prefer generic Kubernetes inputs (`image`, `ingress`, `resources`, `nodeSelector`)
  over environment-specific wiring in templates.
- Validate with `helm lint` and `helm template` using an explicit placeholder image tag.

## Local Validation

```bash
helm lint infra/helm/noora-storybook \
  -f infra/helm/noora-storybook/values-production.yaml \
  --set image.tag=validation
helm template noora-storybook infra/helm/noora-storybook \
  -f infra/helm/noora-storybook/values-production.yaml \
  --set image.tag=validation
```
