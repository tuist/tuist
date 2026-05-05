# Data Export Documentation

This document outlines all data that Tuist can export for customers upon legal request (GDPR, CCPA). **Data is exported for the specific account associated with the requesting user or organization**.

## Export Format

Data is provided in a single compressed archive containing:
- **Database data**: JSON files with account information, projects, command events, and analytics
- **Binary files**: All uploaded files (cache artifacts, app previews, icons)
- **Manifest**: Index of all included files and data

Sensitive authentication data (passwords, tokens) are excluded from exports.

## Exportable Data

### Account & User Data
- User profiles (email, active/inactive status, account settings, preferred locale)
- Organization memberships and roles
- Account billing information and subscriptions
- API tokens, SCIM-scoped account tokens, and project tokens (existence, scopes, names, timestamps, and last-used metadata only; token values and hashes are excluded)
- Custom cache endpoint configurations
- Organization SSO configuration metadata, including the configured SSO provider, provider URL, and full OAuth2 endpoint URLs
- Kura server records (`kura_servers` table): per-account Kura server configuration including region, spec tier, image tag, public URL, status, and volume size
- Kura deployment history (`kura_deployments` table): rollout attempts for the account's Kura servers including image tag, status, error messages, and start/finish timestamps

### Projects & Development
- Project information (names, settings, repositories)
- Command events (CLI usage, build data, performance metrics)
- Cache events and cache action items
- Test cases and test execution results
- Build system data (Xcode graphs, projects, targets)
- Cacheable tasks (Xcode cache analytics: type, status, keys)

### App Previews & Builds
- Preview metadata (versions, platforms, git info)
- App build information

### Alerts & Monitoring
- Alert rules (name, category, metric, deviation thresholds, Slack channel configuration)
- Alert history (triggered alerts with current/previous values, timestamps)

### Analytics Data (ClickHouse)
The following data is stored in ClickHouse for analytics purposes:
- **Build runs** (`build_runs` table): Complete build execution data including duration, status, cache statistics, CI metadata, git information, and custom tags
- **Build issues** (`build_issues` table): Compilation warnings and errors from builds
- **Build files** (`build_files` table): Individual file compilation metrics
- **Build targets** (`build_targets` table): Target/module build performance
- **Cacheable tasks** (`cacheable_tasks` table): Xcode cache task analytics with hit/miss status
- **CAS outputs** (`cas_outputs` table): Content-addressable storage upload/download records
- **Shard plans** (`shard_plans` table): Test sharding plan data including reference, shard count, and granularity
- **Shard plan modules** (`shard_plan_modules` table): Per-shard module assignments with estimated durations
- **Shard plan test suites** (`shard_plan_test_suites` table): Per-shard test suite assignments with estimated durations
- **Shard runs** (`shard_runs` table): Per-shard execution results with status and duration
- **Test runs** (`test_runs` table): Includes `shard_plan_id` linking test results to their shard plan
- **Bundles** (`bundles` table): App bundle metadata (name, app bundle id, version, install/download size, supported platforms, type, git ref/branch/commit). Dual-written from PostgreSQL and backfilled into ClickHouse, so the CH table now holds the full history. PostgreSQL remains the read source until the phase 3 cutover.
- **Bundle artifacts** (`artifacts` table): App bundle artifact tree (paths, sizes, SHA hashes, parent/child hierarchy) per uploaded bundle.
- **Active test cases daily stats** (`test_case_runs_active_daily_stats` materialized view): Pre-aggregated `uniqExactState(test_case_id)` per (`project_id`, `date`, `is_ci`) derived from `test_case_runs`. Powers the Test Cases analytics chart; contains no data not already covered by the source `test_case_runs` table.
- **Test case runs by commit** (`test_case_runs_by_commit` materialized view): Slim projection of `test_case_runs` ordered by (`project_id`, `git_commit_sha`, `scheme`, `is_ci`, `status`, `id`). Powers the cross-run flakiness lookup; contains no data not already covered by the source `test_case_runs` table.
- Build performance metrics

### Non-Exportable Data
- Encrypted passwords and authentication secrets
- Account, SCIM-scoped account, and project token values and encrypted token hashes
- Encrypted SSO client secrets for Okta and custom OAuth2 providers
- Kura cluster kubeconfigs and internal shared secrets (for example `cache_api_key`) used by the control plane to talk to deployment infrastructure
- Kura deployment rollout logs (`kura_deployment_log_lines` ClickHouse table): per-line stdout/stderr captured from `helm` and the rollout script. These are operator-facing infrastructure logs (Kubernetes/Helm output) used by the `/ops` console, not customer content, and may include internal cluster identifiers

## Binary Files

All uploaded files associated with the account are included:
- **Cache artifacts**: Build caches and compiled binaries
- **App previews**: iOS app bundles (.app/.ipa files) and icons  
- **Shard bundles**: Shared `.xctestproducts` bundles stored at `{account_id}/{project_id}/shards/{shard_plan_id}/`

## Export Process

1. Verify user identity and account ownership
2. Collect all database records for the account and associated organizations  
3. Collect all binary files owned by the account
4. Create compressed archive with JSON data files and binary files
5. Provide secure download link

The archive contains everything needed to understand the account's complete data footprint within Tuist.
