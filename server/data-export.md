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
- Kura server records (`kura_servers` table): per-account Kura server configuration including region, image tag, public URL, and status
- Kura deployment history (`kura_deployments` table): rollout attempts for the account's Kura servers including image tag, status, error messages, and start/finish timestamps
- GitHub App installation metadata (`github_app_installations` table): the installation ID GitHub assigned, the GitHub instance the App lives on (`client_url`, e.g. `https://github.com` or a customer's GitHub Enterprise Server host), the App's `app_id`/`app_slug`/`client_id`, and the GitHub-side management `html_url`. The accompanying `client_secret`, `private_key` (PEM), and `webhook_secret` are stored encrypted at rest and are excluded from exports as authentication secrets.
- VCS connections (`vcs_connections` table): the link between a Tuist project and an external repository handle (provider, repository full name, the originating GitHub App installation, and the user who created the connection)

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
- Automation alerts (`automation_alerts` table): per-project flaky-test automations, including name, enabled flag, monitor type (`flakiness_rate` / `flaky_run_count`), evaluation cadence, baseline established timestamp, and the trigger / recovery configuration as JSON. The configuration includes the comparison threshold, comparison operator, `window_type` (`last_days` for calendar windows or `rolling` for count-based windows), the day-string `window` (e.g. `30d`) used in `last_days` mode, and the integer `rolling_window_size` (e.g. `100` runs) used in `rolling` mode. Trigger and recovery action lists are stored alongside the configuration (state changes, label adds/removes, Slack channel references).
- Automation alert events (`automation_alert_events` table): per-test-case trigger and recovery records produced by automation alerts (alert id, test case id, status, timestamps).

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

### Outbound Webhooks
- Webhook endpoints (`webhook_endpoints` table): per-account HTTPS destinations subscribed to Tuist events. Exports include endpoint name, subscribed event types (`test_case.created`, `test_case.updated`, `preview.uploaded`, `preview.deleted`), and timestamps. The endpoint URL and signing secret are stored Vault-encrypted at rest and are excluded from exports as authentication material.
- Webhook delivery attempts (`webhook_delivery_attempts` table, ClickHouse): per-attempt audit log generated by `Tuist.Webhooks.Workers.DeliveryWorker`. Exports include the event id and type, attempt number, delivery status (`delivered` / `failed`), the JSON payload Tuist sent (`request_body`), the response status / headers / body returned by the upstream, any error string, the duration in milliseconds, and the attempt timestamp. Stored in a MergeTree with `TTL inserted_at + INTERVAL 7 DAY DELETE`, so rows older than 7 days are dropped automatically.

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
- **Active test cases daily stats** (`test_case_runs_active_daily_stats` materialized view): Exact daily presence rows per (`project_id`, `date`, `is_ci`, `test_case_id`) derived from `test_case_runs`. Powers the Test Cases analytics chart; contains no data not already covered by the source `test_case_runs` table.
- **Test case runs by commit** (`test_case_runs_by_commit` materialized view): Slim projection of `test_case_runs` ordered by (`project_id`, `git_commit_sha`, `scheme`, `is_ci`, `status`, `id`). Powers the cross-run flakiness lookup; contains no data not already covered by the source `test_case_runs` table.
- **Per-test-case daily run stats** (`test_case_run_daily_stats_per_case` materialized view): AggregatingMergeTree keyed on (`project_id`, `date`, `test_case_id`) with `count` and `sumState(toUInt8(is_flaky))` aggregate states. Powers the flaky-test automation engine's per-test windowed comparisons; contains no data not already covered by the source `test_case_runs` table.
- **Per-environment last-run timestamps** (`test_cases.last_ran_at_ci`, `test_cases.last_ran_at_local` columns): Denormalized timestamps tracking the most recent CI and local run per test case. Maintained by the ingestion path on every test run; contains no data not already covered by the source `test_case_runs` table.
- **Test case events** (`test_case_events` table): Audit log of state changes on a test case — `first_run`, `marked_flaky`/`unmarked_flaky`, `muted`/`unmuted`, `skipped`/`unskipped`. Each row records the `test_case_id`, the `event_type`, the `inserted_at` timestamp, and attribution columns: `actor_id` (the account that performed the change when initiated by a user; null for system/automation writes) and `alert_id` (the `automation_alerts.id` whose action produced the change; null otherwise). Powers the test case history timeline.
- Build performance metrics

### Non-Exportable Data
- Encrypted passwords and authentication secrets
- Account, SCIM-scoped account, and project token values and encrypted token hashes
- Encrypted SSO client secrets for Okta and custom OAuth2 providers
- Internal replication bookkeeping (e.g., `bundles.artifacts_replicated_to_ch`) used to drive the PG → ClickHouse artifacts backfill
- Internal Kura shared secrets used by the control plane and Kura runtime extensions
- Encrypted GitHub App credentials (`client_secret`, `private_key`, `webhook_secret` on `github_app_installations`)
- Slack bot access tokens and incoming-webhook URLs (treated as bearer credentials)
- Outbound webhook endpoint URLs and signing secrets on `webhook_endpoints` (treated as bearer credentials — path/query tokens often appear in destination URLs)
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
