# Tuist Search Service (TypeSense)

This service powers full-text search for Tuist documentation, API references, community forum, and GitHub issues/PRs using TypeSense.

## Key Boundaries
- TypeSense engine: deployed via Kamal to `search.tuist.dev`
- DocSearch scraper configs: `search/config/docsearch*.json`
- Python indexers: `search/bin/index-docc.py`, `search/bin/index-github.py`
- Operational scripts: `search/bin/scrape`, `search/bin/scrape-cron`, `search/bin/index-docc`, `search/bin/index-github`

## Architecture
- **TypeSense** (v27.1) stores and serves search data via API
- **DocSearch scraper** crawls tuist.dev and community.tuist.dev, feeding content into TypeSense
- **Custom Python indexers** index ProjectDescription DocC API docs and GitHub issues/PRs
- A server-side cron job runs all indexers daily at 04:00 UTC

## Deployment
- Deployed with Kamal to `91.99.179.13` (ARM64)
- Registry: `localhost:5000` (local to the server)
- Domain: `search.tuist.dev` (HTTPS via Kamal proxy)
- Secrets managed via 1Password (`search` vault)
- Deploy: `mise run deploy` (from `search/` directory)
