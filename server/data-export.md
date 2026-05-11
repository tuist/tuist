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
- Organization records (account handle/name, creator relationship, and timestamps)
- Organization memberships and roles (user, organization, role, and timestamps)
- Account billing information and subscriptions
- API tokens, SCIM-scoped account tokens, and project tokens (existence, scopes, names, timestamps, and last-used metadata only; token values and hashes are excluded)
- Custom cache endpoint configurations
- Organization SSO configuration metadata, including the configured SSO provider, provider URL, and full OAuth2 endpoint URLs

### Projects & Development
- Project information (account relationship, handle/name, build system, default branch, visibility/settings, repositories, and timestamps)
- Command events (CLI usage, build data, performance metrics)
- Cache events and cache action items
- Test cases and test execution results
- Build system data (Xcode graphs, projects, targets)
- Cacheable tasks (Xcode cache analytics: type, status, keys)

### App Previews & Builds
- Preview metadata (versions, platforms, git info)
- App build information

### Alerts & Monitoring
- Alert rules (name, category, metric, deviation thresholds, Slack channel configuration, baseline established timestamp)
- Alert history (triggered alerts with current/previous values, timestamps)

### Managed GitHub Actions Runners
- **Per-account configuration** (Postgres `accounts.runner_max_concurrent`): the customer's account-wide concurrent runner budget. `0` means runners are disabled for the account; `N > 0` is the active cap.
- **Active claim coordination** (Postgres `runner_claims`): one row per currently-claimed workflow_job. Columns: `workflow_job_id` (GitHub's job id, PK), `account_id`, `fleet_name` (the RunnerPool name the claim is bound to), `pod_name` (the SA / Pod that won the claim), `claimed_at`. Rows are deleted on completion / release / stale recovery; steady-state size is bounded by the number of in-flight runners.
- **Workflow_job lifecycle** (ClickHouse `runner_jobs`, ReplacingMergeTree on `workflow_job_id`): one logical row per workflow_job carrying the full lifecycle from `queued` → `claimed` → `running` → `completed`. Columns include the GitHub correlation fields (`workflow_job_id`, `workflow_run_id`, `run_attempt`, `job_name`, `head_branch`, `head_sha`, `repo`), lifecycle state (`status`, `conclusion`), timestamps (`enqueued_at`, `claimed_at`, `started_at`, `completed_at`, `updated_at`), and binding (`pod_name`, `runner_name`). Powers the customer-facing "queued / running / recent runs" surfaces.
- **Kubernetes-side state** (`RunnerPool` CR + Pods / ServiceAccounts in the `tuist-runners` namespace): operational metadata only — pool name, dispatch label, image, replica count, owner labels on Pods. Reconciled by the runners-controller.
- **JIT runner configs**: the GitHub-issued JIT credential the dispatch endpoint mints for each runner registration is an ephemeral authentication secret and is never persisted server-side. Only the resulting `runner_name` (the GitHub-side runner label) is recorded in `runner_jobs`.

### Slack Integration
- Account-level Slack installation records (workspace id/name, bot user id; bot access tokens are excluded as authentication secrets)
- Per-channel Slack webhook destinations stored on projects, alert rules, and project flaky-test settings (channel id, channel name; the encrypted webhook URL itself is excluded as an authentication secret)
- Per-action Slack webhook destinations stored on automation alerts (channel id, channel name; the encrypted webhook URL embedded in the action payload is excluded as an authentication secret)

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
- **Bundles** (`bundles` table): App bundle metadata (name, app bundle id, version, install/download size, supported platforms, type, git ref/branch/commit).
- **Bundle artifacts** (`artifacts` table): App bundle artifact tree (paths, sizes, SHA hashes, parent/child hierarchy) per uploaded bundle.
- **Active test cases daily stats** (`test_case_runs_active_daily_stats` materialized view): Pre-aggregated `uniqExactState(test_case_id)` per (`project_id`, `date`, `is_ci`) derived from `test_case_runs`. Powers the Test Cases analytics chart; contains no data not already covered by the source `test_case_runs` table.
- **Test case runs by commit** (`test_case_runs_by_commit` materialized view): Slim projection of `test_case_runs` ordered by (`project_id`, `git_commit_sha`, `scheme`, `is_ci`, `status`, `id`). Powers the cross-run flakiness lookup; contains no data not already covered by the source `test_case_runs` table.
- **Per-test-case daily run stats** (`test_case_run_daily_stats_per_case` materialized view): AggregatingMergeTree keyed on (`project_id`, `date`, `test_case_id`) with `count` and `sumState(toUInt8(is_flaky))` aggregate states. Powers the flaky-test automation engine's per-test windowed comparisons; contains no data not already covered by the source `test_case_runs` table.
- **Per-environment last-run timestamps** (`test_cases.last_ran_at_ci`, `test_cases.last_ran_at_local` columns): Denormalized timestamps tracking the most recent CI and local run per test case. Maintained by the ingestion path on every test run; contains no data not already covered by the source `test_case_runs` table.
- Build performance metrics

### Non-Exportable Data
- Encrypted passwords and authentication secrets
- Account, SCIM-scoped account, and project token values and encrypted token hashes
- Encrypted SSO client secrets for Okta and custom OAuth2 providers
- Slack bot access tokens and incoming-webhook URLs (treated as bearer credentials)
- GitHub-issued JIT runner configs (minted on demand for runner Pods at dispatch time and never persisted server-side)

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
