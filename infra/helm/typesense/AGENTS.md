# Typesense chart

Standalone chart for the Tuist Typesense search engine, moved from the Kamal
deployment in `search/` into the cluster. It powers the public docs and forum
search that `search.tuist.dev` serves, and is the retrieval engine an in-cluster
agent search service will delegate to in a follow-up.

## Layout

- `Deployment` runs the Typesense server directly (`/opt/typesense-server`) off
  the `ghcr.io/tuist/search` image, backed by a single ReadWriteOnce PVC at
  `/data`. `Recreate` strategy, because only one pod may mount the volume.
- `CronJob` runs the DocC and GitHub indexers (`run-indexers.sh`) against the
  Service. The DocSearch website scraper is not included; like the Kamal
  deployment it runs separately because it crawls the public site.
- `Ingress` exposes `search.tuist.dev` through ingress-nginx with a
  cert-manager certificate; external-dns publishes the record.
- `TYPESENSE_API_KEY` and `GITHUB_TOKEN` come from 1Password via an
  ExternalSecret in production, or inline for CI and dev.

## Cutover

Merging deploys a parallel in-cluster instance without touching the Kamal box or
DNS. `search.tuist.dev` still resolves to the Kamal node until its Cloudflare
record is released, because external-dns will not take over a record it does not
own. Reindex the in-cluster instance and verify the `tuist` and `forum-topics`
collections before repointing DNS, or docs-site search breaks during the gap.

## Validation

```bash
helm template infra/helm/typesense -f infra/helm/typesense/values-ci.yaml
helm template infra/helm/typesense -f infra/helm/typesense/values-production.yaml -f infra/helm/typesense/values-ci.yaml
```

## Related Context

- Parent boundary: `infra/helm/AGENTS.md`
- Image and indexers: `search/AGENTS.md`
