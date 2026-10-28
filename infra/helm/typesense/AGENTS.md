# Typesense Chart

- Keep a single server with `Recreate` strategy for its ReadWriteOnce `/data` PVC.
- Preserve idempotent key-bootstrap hooks: a fresh volume must register the public read-only search key, never expose the admin key. Release-indexer bootstrap follows key bootstrap and must succeed without a GitHub token by skipping release indexing.
- The public search UI queries `projectdescription`, `github-issues`, `github-releases`, `tuist`, and `forum-topics`. Verify required collections and the public key before routing traffic to a fresh instance; scheduled indexers alone do not guarantee immediate readiness.
- DocSearch configs come from `search/config/docsearch*.json`, synced by [the deployment workflow](../../../.github/workflows/typesense-deployment.yml). Image/indexer changes belong in `search/`.

Validate from the repository root with placeholder credentials:

```bash
helm template infra/helm/typesense -f infra/helm/typesense/values-ci.yaml
helm template infra/helm/typesense -f infra/helm/typesense/values-production.yaml -f infra/helm/typesense/values-ci.yaml
```
