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
- User profiles (email, account settings, preferred locale)
- Organization memberships and roles
- Account billing information and subscriptions
- API tokens and project tokens (existence only, not values)
- Custom cache endpoint configurations
- Organization SSO configuration metadata, including the configured SSO provider, provider URL, and full OAuth2 endpoint URLs

### Projects & Development
- Project information (names, settings, repositories)
- Command events (CLI usage, build data, performance metrics)
- Cache events and cache action items
- Test cases and test execution results
- Build system data (Xcode graphs, projects, targets)
- Cacheable tasks (Xcode cache analytics: type, status, keys)

### Kura Servers & Rollouts
- **Kura servers** (`kura_servers` table): Per-account server records including region, customer-facing spec, volume size, lifecycle status, public URL, current image tag, opaque provisioner handle, provisioner metadata, and timestamps
- **Kura deployments** (`kura_deployments` table): Rollout attempts linked to an account and Kura server, including target cluster identifier, requested image tag, rollout status, error message, Oban job ID, start/finish timestamps, and audit timestamps
- **Derived cache endpoints** (`account_cache_endpoints` table): The Kura public URLs mirrored into the account's cache endpoint list while a server is active

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
- **Bundle artifacts** (`artifacts` table): App bundle artifact tree (paths, sizes, SHA hashes, parent/child hierarchy) per uploaded bundle.
- **Active test cases daily stats** (`test_case_runs_active_daily_stats` materialized view): Pre-aggregated `uniqExactState(test_case_id)` per (`project_id`, `date`, `is_ci`) derived from `test_case_runs`. Powers the Test Cases analytics chart; contains no data not already covered by the source `test_case_runs` table.
- **Kura deployment log lines** (`kura_deployment_log_lines` table): Ordered stdout/stderr captured during Kura provision, rollout, and destroy operations for an account's servers. These logs may include Kubernetes resource names, public URLs, and operator-visible rollout diagnostics.
- Build performance metrics

### Non-Exportable Data
- Encrypted passwords and authentication secrets
- Encrypted SSO client secrets for Okta and custom OAuth2 providers
- Internal replication bookkeeping (e.g., `bundles.artifacts_replicated_to_ch`) used to drive the PG → ClickHouse artifacts backfill
- Kura cluster kubeconfigs and internal shared secrets (for example `cache_api_key`) used by the control plane to talk to deployment infrastructure

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
