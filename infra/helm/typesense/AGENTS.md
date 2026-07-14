# Typesense chart

Standalone chart for the Tuist Typesense search engine, moved from the Kamal
deployment in `search/` into the cluster. It powers the public docs and forum
search that `search.tuist.dev` serves, and is the retrieval engine an in-cluster
agent search service will delegate to in a follow-up.

## Layout

- `Deployment` runs the Typesense server directly (`/opt/typesense-server`) off
  the `ghcr.io/tuist/search` image, backed by a single ReadWriteOnce PVC at
  `/data`. `Recreate` strategy, because only one pod may mount the volume.
- `typesense-indexers` `CronJob` runs the DocC and GitHub indexers
  (`run-indexers.sh`) against the Service, and `typesense-scraper` `CronJob` runs
  the DocSearch crawler for the docs and forum configs. The configs come from the
  `docsearch-configs` ConfigMap, which the deploy workflow syncs from
  `search/config/docsearch*.json`.
- `typesense-keybootstrap` is a `post-install`/`post-upgrade` hook `Job` that
  idempotently registers the public read-only search key
  (`typesense.searchKey`) on the instance using the admin key. Typesense stores
  non-bootstrap keys inside its own data, so a fresh volume needs this to accept
  the key the docs website and the `search_tuist` MCP tool present.
- `typesense-release-indexer-bootstrap` runs after the key bootstrap on each
  install or upgrade so the `github-releases` collection is available
  immediately when a GitHub token is configured. Tokenless installations skip
  release indexing successfully. The recurring indexer CronJob refreshes it
  daily afterward.
- `Ingress` exposes `search.tuist.dev` through ingress-nginx with a
  cert-manager certificate. The production overlay annotates it
  `external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"` so external-dns
  manages the record and keeps it proxied.
- `TYPESENSE_API_KEY` and `GITHUB_TOKEN` come from 1Password via an
  ExternalSecret in production (or inline for CI and dev). The ExternalSecret
  reads two items through the per-env `onepassword` ClusterSecretStore, which is
  scoped to the `tuist-k8s-<env>` vault: `TYPESENSE_API_KEY/password` and
  `SEARCH_GITHUB_TOKEN/password`. These mirror the item names in the `cache`
  vault that the Kamal deployment reads directly; copy them into the per-env
  vault (do not move them while the Kamal box is still live).

## Collections

Five collections back search, all populated in-cluster:

- `projectdescription` (DocC API), `github-issues`, and `github-releases` come from the
  `typesense-indexers` CronJob (`index-docc`, `index-github`, `index-github-releases`).
- `tuist` (docs) and `forum-topics` (forum) come from the `typesense-scraper`
  CronJob (`typesense/docsearch-scraper` with the `docsearch-configs` ConfigMap).

The public docs and forum search UI (`server/assets/docs/hooks/docs-search-hook.js`)
queries all five collections, so they must exist on any instance that serves the
UI. On a fresh volume the CronJobs run on their schedule; trigger them
once with `kubectl create job --from=cronjob/typesense-indexers` (and the
scraper) to populate immediately.

## Cutover

The chart bootstraps everything the instance needs on its own: the key-bootstrap
hook registers the search key, and the two CronJobs populate the collections. The
one remaining manual step is DNS. `search.tuist.dev` keeps resolving to the old
Kamal node until its manually-created Cloudflare record is deleted, because
external-dns will not take over a record it does not own. Delete that record and,
within its 1-minute interval, external-dns recreates `search.tuist.dev` pointing
at the ingress load balancer (proxied, per the ingress annotation) and reconciles
it from then on. Do this only once the collections are populated and the key is
registered, or docs-site and forum search break during the gap.

## Validation

```bash
helm template infra/helm/typesense -f infra/helm/typesense/values-ci.yaml
helm template infra/helm/typesense -f infra/helm/typesense/values-production.yaml -f infra/helm/typesense/values-ci.yaml
```

## Related Context

- Parent boundary: `infra/helm/AGENTS.md`
- Image and indexers: `search/AGENTS.md`
