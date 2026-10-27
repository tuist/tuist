# Search

Typesense indexes docs, the community forum, DocC, and GitHub issues/PRs/releases.

- Edit scraper configuration in `search/config/docsearch*.json`; deployment syncs
  it into the chart's ConfigMap. Do not maintain a second copy in Helm values.
- Indexer scripts in `search/bin/` are baked into the image; the chart runs them
  and DocSearch as separate CronJobs and bootstraps the public read-only key.
- The admin key and GitHub token come from External Secrets/1Password; only the
  read-only search key belongs in chart values.
- Packaging and deployment live in `infra/helm/typesense/` and
  `.github/workflows/typesense-deployment.yml`.
