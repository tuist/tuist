# Noora Storybook Helm Chart

Standalone chart for the public Noora Storybook deployment at
`storybook.noora.tuist.dev`.

This chart is intentionally separate from `infra/helm/tuist/` so Storybook can ship on
its own workflow and release boundary instead of riding the Tuist server rollout.

Because it runs on the shared production workload cluster, the chart also hardens the
runtime by using a dedicated ServiceAccount, disabling service-account token automount,
running the container as non-root with a restricted security context, and enabling a
default-deny NetworkPolicy in production.

## Local validation

Lint the chart:

```bash
helm lint infra/helm/noora-storybook \
  -f infra/helm/noora-storybook/values-ci.yaml
```

Render the production manifests:

```bash
helm template noora-storybook infra/helm/noora-storybook \
  -f infra/helm/noora-storybook/values-production.yaml \
  -f infra/helm/noora-storybook/values-ci.yaml
```

## Production deploy

The production workflow deploys this chart into the `noora` namespace on the managed
cluster:

```bash
helm upgrade --install noora-storybook infra/helm/noora-storybook \
  --namespace noora --create-namespace \
  -f infra/helm/noora-storybook/values-production.yaml \
  --set image.tag=<sha-tag>
```

`external-dns` reconciles the Ingress hostname into Cloudflare and the chart creates
an explicit `cert-manager.io/v1` `Certificate` for the `storybook.noora.tuist.dev`
secret through the cluster's `letsencrypt-cloudflare` issuer.
