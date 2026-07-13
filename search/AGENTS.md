# Tuist Search Service (TypeSense)

This service powers full-text search for Tuist documentation, API references, community forum, and GitHub issues/PRs using TypeSense.

## Key Boundaries
- TypeSense engine: deployed to Kubernetes via `infra/helm/typesense`, served at `search.tuist.dev`
- DocSearch scraper configs: `search/config/docsearch*.json` (single source; the deploy workflow syncs them into the `docsearch-configs` ConfigMap)
- Python indexers: `search/bin/index-docc.py`, `search/bin/index-github.py`
- Indexer scripts baked into the image: `search/bin/index-docc`, `search/bin/index-github`, `search/bin/run-indexers.sh`

## Architecture
- **TypeSense** (v27.1) stores and serves search data via API
- **DocSearch scraper** crawls tuist.dev and community.tuist.dev, feeding the `tuist` and `forum-topics` collections
- **Custom Python indexers** index ProjectDescription DocC API docs (`projectdescription`) and GitHub issues/PRs (`github-issues`)
- In the cluster, the DocC/GitHub indexers run as the `typesense-indexers` CronJob and the DocSearch scraper as the `typesense-scraper` CronJob; the read-only search key is registered on each deploy by the chart's key-bootstrap Job

## Deployment
- Deployed to the production Kubernetes cluster via `infra/helm/typesense` and `.github/workflows/typesense-deployment.yml` (push to `main` on `search/**` or `infra/helm/typesense/**`)
- Image: `ghcr.io/tuist/search` (built from this directory's `Dockerfile`)
- Domain: `search.tuist.dev` via ingress-nginx with a cert-manager certificate
- Secrets: the admin API key and GitHub token come from 1Password via the chart's ExternalSecret; the search key is public and lives in the chart values
- See `infra/helm/typesense/AGENTS.md` for the chart, collections, and cutover notes
