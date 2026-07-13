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

## Collections

Four collections back search, populated by two different mechanisms:

- `projectdescription` (DocC API) and `github-issues` are produced by the
  bundled indexers (`index-docc`, `index-github`) that the reindex CronJob runs.
- `tuist` (docs) and `forum-topics` (forum) are produced by the DocSearch
  scraper (`typesense/docsearch-scraper` with `search/config/docsearch*.json`),
  which crawls the public site from its own container. It is not part of this
  chart and today runs out-of-band against the Kamal box.

The public docs and forum search UI (`server/assets/docs/hooks/docs-search-hook.js`)
queries `tuist` and `forum-topics`, so those two must exist on any instance that
serves the UI.

## Cutover

Merging deploys a parallel in-cluster instance without touching the Kamal box or
DNS. `search.tuist.dev` keeps resolving to the Kamal node until its Cloudflare
record is released, because external-dns will not take over a record it does not
own. Before repointing DNS, all four collections must be populated on the
in-cluster instance: the CronJob covers `projectdescription` and `github-issues`,
and the DocSearch scraper must be run against the new Service to populate `tuist`
and `forum-topics` (migrating the scraper into the cluster is a required
pre-cutover step). Cutting over before those two exist breaks docs-site and
forum search.

## Validation

```bash
helm template infra/helm/typesense -f infra/helm/typesense/values-ci.yaml
helm template infra/helm/typesense -f infra/helm/typesense/values-production.yaml -f infra/helm/typesense/values-ci.yaml
```

## Related Context

- Parent boundary: `infra/helm/AGENTS.md`
- Image and indexers: `search/AGENTS.md`
