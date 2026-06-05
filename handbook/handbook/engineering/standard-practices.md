---
{
  "title": "Standard practices",
  "titleTemplate": ":title | Engineering | Tuist Handbook",
  "description": "Standard practices are the set of guidelines that Tuist engineers follow to ensure that the codebase is consistent, maintainable, and scalable."
}
---
# Standard practices

## Trunk-based development

Tuist repositories follow [trunk-based development](<https://en.wikipedia.org/wiki/Branching_(version_control)>) with `main` as the default branch, requiring at least two approvals for pull requests and CI to pass before merging. CI checks should include thorough testing, linting, and code formatting that ensures code style consistency throughout the organization.

## CLI backward-compatibility window

We support the Tuist CLI releases from the last **3 months** against the production server. Customers do not all upgrade on our cadence, so a server change that breaks an older but still-supported CLI is a production regression for them, not just a stale client.

This is not theoretical. The server once stopped attaching the cryptographic signature to cache-artifact downloads. Newer CLIs had already stopped requiring it, but older CLIs still ran the signature verifier and rejected every cache response, dropping affected customers' cache hit rate to 0% and wiping out their CI until they could upgrade.

To guard against this, every production deployment runs a backward-compatibility acceptance suite against the freshly-deployed canary using the **oldest CLI version we still support**, not just the CLI built from `main`. It exercises the module cache pull path (the one the signature incident broke) and blocks promotion to production if it fails.

The authoritative pin for the oldest supported release is the `MIN_SUPPORTED_TUIST_VERSION` env var in [`server-production-deployment.yml`](https://github.com/tuist/tuist/blob/main/.github/workflows/server-production-deployment.yml). Bump it as the 3-month window slides forward. The suite itself lives in `e2e/module_cache_backward_compat.bats`.
