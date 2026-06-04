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
- Agent registration audit records (`agent_registrations`, `agent_registration_events`, and `agent_auth_jtis` tables): registration type/status, requested credential type, verified email address, claim attempt id, claim and OTP expiry timestamps, claim request / completion IP metadata, claimed user relationship, linked account-token id or JWT id, ID-JAG issuer/subject/audience/client metadata, replay-protection `jti` records, append-only state-change events (`created`, `claim_resent`, `otp_failed`, `claimed`, `expired`, `revoked`), event IP metadata, event metadata, and timestamps. The claim token hash, claim-view token hash, OTP hash, issued API key value, and signed JWT value are excluded from exports as authentication secrets.
- Custom cache endpoint configurations (`account_cache_endpoints` table): account-specific custom cache endpoints and active regional Kura endpoint mirrors. Legacy account-level Kura global endpoint rows matching `https://<lowercase-account-handle>.kura.tuist.dev` are no longer stored separately; they are removed by the Kura global-endpoint cleanup migration.
- Organization SSO configuration metadata, including the configured SSO provider, provider URL, and full OAuth2 endpoint URLs
- Kura server records (`kura_servers` table): per-account Kura server configuration including region, image tag, public URL, status, and the observed-state projection (`observed_image_tag`, `last_observed_at`) recording which image the backing cluster reports running and when it was last observed
- Kura deployment history (`kura_deployments` table): rollout attempts for the account's Kura servers including image tag, status, error messages, and start/finish timestamps
- GitHub App installation metadata (`github_app_installations` table): the installation ID GitHub assigned, the GitHub instance the App lives on (`client_url`, e.g. `https://github.com` or a customer's GitHub Enterprise Server host), the App's `app_id`/`app_slug`/`client_id`, and the GitHub-side management `html_url`. The accompanying `client_secret`, `private_key` (PEM), and `webhook_secret` are stored encrypted at rest and are excluded from exports as authentication secrets.
- VCS connections (`vcs_connections` table): the link between a Tuist project and an external repository handle (provider, repository full name, the originating GitHub App installation, and the user who created the connection)
- Artifact retention cursors (`artifact_retention_cursors` table): per-account cleanup progress for DB-backed artifact families. Exports include the artifact type plus the last processed metadata cursor (`after_inserted_at`, `after_id`) used to avoid re-processing blobs that have already been purged from object storage.

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
- **Per-account availability**: whether runners are enabled for an account is gated solely by the `:runners` feature flag (`Tuist.FeatureFlags.runners_enabled?/1`), not by any column on the account. No per-account runner configuration is stored as customer data.
- **Runner profiles** (Postgres `runner_profiles`): account-scoped named bundles of `(vcpus, memory_gb)` that customers reference from `runs-on:` as `tuist-<name>`. Columns: `id` (PK), `account_id`, `name`, `vcpus`, `memory_gb`, `inserted_at`, `updated_at`. The dispatch path resolves `(account, requested-label)` through these rows to the matching shape pool. The shape pool itself is operator-managed in Kubernetes and not customer data.
- **Active claim coordination** (Postgres `runner_claims`): one row per currently-claimed workflow_job. Columns: `workflow_job_id` (GitHub's job id, PK), `account_id`, `fleet_name` (the RunnerPool name the claim is bound to), `pod_name` (the SA / Pod that won the claim), `claimed_at`, `lifecycle_state` (`claimed` during the JIT-mint window, `running` once the runner has registered with GitHub), and `runner_name` (the GitHub-side runner label, populated when `lifecycle_state` flips to `running`). Rows are deleted on completion / release / stale recovery; steady-state size is bounded by the number of in-flight runners.
- **Runner billing sessions** (Postgres `runner_sessions`): append-only record of every runner Pod we provisioned, keyed off the Pod lifecycle rather than the workflow_job's GitHub-reported runtime. Columns: `id` (PK), `account_id`, `workflow_job_id`, `fleet_name`, `pod_name`, `runner_name`, `repository` (denormalized `owner/name` handle from the workflow_job for billing-page scope filters), `workflow_name` (denormalized for the same), `started_at` (claim-win — proxy for Pod creation), `ended_at` (set by the runners-controller via `POST /api/internal/runners/pods/stopped` when it observes the Pod's container terminate; NULL while still in flight). Drives metered-compute invoicing via `Tuist.Runners.Billing`. Retries (`Jobs.record_queued/1`) produce additional rows so the customer is billed for every Pod they actually held.
- **Workflow_job lifecycle** (ClickHouse `runner_jobs`, ReplacingMergeTree on `workflow_job_id`): one logical row per workflow_job carrying the full lifecycle from `queued` → `claimed` → `running` → `completed`. Columns include the GitHub correlation fields (`workflow_job_id`, `workflow_run_id`, `run_attempt`, `workflow_name`, `job_name`, `head_branch`, `head_sha`, `repository`), the GitHub ref-scope fields used to scope the self-hosted Actions cache (`default_branch`, `base_ref`, `untrusted_fork`), lifecycle state (`status`, `conclusion`), timestamps (`enqueued_at`, `claimed_at`, `started_at`, `completed_at`, `updated_at`), and binding (`pod_name`, `runner_name`). Powers the customer-facing "queued / running / recent runs" surfaces.
- **Kubernetes-side state** (`RunnerPool` CR + Pods / ServiceAccounts in the `tuist-runners` namespace): operational metadata only — pool name, dispatch label, image, replica count, owner labels on Pods. Reconciled by the runners-controller.
- **JIT runner configs**: the GitHub-issued JIT credential the dispatch endpoint mints for each runner registration is an ephemeral authentication secret and is never persisted server-side. Only the resulting `runner_name` (the GitHub-side runner label) is recorded in `runner_jobs`.

### Slack Integration
- Account-level Slack installation records (workspace id/name, bot user id; bot access tokens are excluded as authentication secrets)
- Per-channel Slack webhook destinations stored on projects, alert rules, and project flaky-test settings (channel id, channel name; the encrypted webhook URL itself is excluded as an authentication secret)
- Per-action Slack webhook destinations stored on automation alerts (channel id, channel name; the encrypted webhook URL embedded in the action payload is excluded as an authentication secret)

### Outbound Webhooks
- Webhook endpoints (`webhook_endpoints` table): per-account HTTPS destinations subscribed to Tuist events. Exports include endpoint name, subscribed event types (`test_case.created`, `test_case.updated`, `preview.created`, `preview.deleted`), and timestamps. The endpoint URL and signing secret are stored Vault-encrypted at rest and are excluded from exports as authentication material.
- Webhook delivery attempts (`webhook_delivery_attempts` table, ClickHouse): per-attempt audit log generated by `Tuist.Webhooks.Workers.DeliveryWorker`. Exports include the event id and type, attempt number, delivery status (`delivered` / `failed`), the JSON payload Tuist sent (`request_body`), the response status / headers / body returned by the upstream, any error string, the duration in milliseconds, and the attempt timestamp. Stored in a MergeTree partitioned monthly; retained indefinitely so the dashboard can surface historical deliveries for debugging.

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
- Agent registration claim token hashes, claim-view token hashes, OTP hashes, issued API key values, and signed JWT values
- Encrypted SSO client secrets for Okta and custom OAuth2 providers
- Internal replication bookkeeping (e.g., `bundles.artifacts_replicated_to_ch`) used to drive the PG → ClickHouse artifacts backfill
- Internal Kura shared secrets used by the control plane and Kura runtime extensions
- Managed Kura operational traces retained in Tempo: service/resource metadata (including `kura.tenant_id`, `kura.region`, serving-node `geo.country.iso_code` / `geo.region.iso_code`) and request spans (including route, status, duration, and best-effort client `geo.country.iso_code` / `geo.region.iso_code`). This telemetry is used for platform observability and incident response, and is not part of the customer export archive today.
- Encrypted GitHub App credentials (`client_secret`, `private_key`, `webhook_secret` on `github_app_installations`)
- Slack bot access tokens and incoming-webhook URLs (treated as bearer credentials)
- Outbound webhook endpoint URLs and signing secrets on `webhook_endpoints` (treated as bearer credentials — path/query tokens often appear in destination URLs)
- GitHub-issued JIT runner configs (minted on demand for runner Pods at dispatch time and never persisted server-side)

## Binary Files

All uploaded files associated with the account are included:
- **Cache artifacts**: Build caches and compiled binaries
- **App previews**: iOS app bundles (.app/.ipa files) and icons  
- **Shard bundles**: Shared `.xctestproducts` bundles stored at `{account_id}/{project_id}/shards/{shard_plan_id}/`

## Data Retention

Stored artifact blobs are subject to plan-based retention. Once an artifact is
older than its retention window, its binary is removed from object storage by a
daily cleanup process; the associated metadata rows (build runs, test runs,
preview records, shard plans) are kept so analytics and dashboards remain
intact. Retention windows, in days, by plan:

| Artifact | Air / Open Source | Pro | Enterprise |
| --- | --- | --- | --- |
| Cache artifacts (Xcode compilation, module, Gradle) | 14 | 30 | 90 |
| App preview builds and icons | 60 | 180 | 365 |
| Build archives | 30 | 90 | 365 |
| Test run attachments | 30 | 90 | 365 |
| Shard bundles | 7 | 14 | 30 |

Retention status is computed when cleanup runs. Cache artifacts use the object
storage `last_modified` timestamp, while previews, build archives, test
attachments, and shard bundles use their database `inserted_at` timestamp. The
active account plan determines the applicable window, with Air used when an
account has no active subscription.

Tuist stores per-account cleanup progress for DB-backed artifact families so
daily retention jobs can resume after previously-purged metadata rows without
issuing repeated object-storage deletes. This is not a per-artifact purge
ledger; retention is still derived from the timestamps and account plan above.
An export reflects the artifacts present at export time; binaries already
purged under these windows are no longer available, though their metadata and
the account-level cleanup cursor are still exported.

## Export Process

1. Verify user identity and account ownership
2. Collect all database records for the account and associated organizations  
3. Collect all binary files owned by the account
4. Create compressed archive with JSON data files and binary files
5. Provide secure download link

The archive contains everything needed to understand the account's complete data footprint within Tuist.
