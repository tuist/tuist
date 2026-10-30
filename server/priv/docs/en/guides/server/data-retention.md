---
{
  "title": "Data retention",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how long Tuist keeps downloadable artifacts and dashboard activity data."
}
---
# Data retention {#data-retention}

Tuist applies separate retention policies to uploaded artifact files and the records used for dashboards and insights. Deleting an expired artifact file does not delete its associated insights records.

For artifact files, the hosted Tuist server uses plan-based windows capped at 30 days. Artifact cleanup is disabled by default on self-hosted instances, where operators can opt in and configure a separate window for each supported artifact type.

## Artifact files {#artifact-files}

### Hosted Tuist server {#hosted-artifact-files}

These windows define how long artifact files remain available on the hosted Tuist server.

| Artifact | Air and Open Source | Pro | Enterprise |
| --- | --- | --- | --- |
| Cache artifacts, including Xcode cache, module cache, Gradle cache, Bazel remote-cache files, and GitLab CI cache archives from Tuist Runners | 14 days | 30 days | 30 days |
| App preview builds and icons | 30 days | 30 days | 30 days |
| Build archives | 7 days | 30 days | 30 days |
| Run artifacts, including result bundles and session archives | 7 days | 30 days | 30 days |
| Test run attachments | 30 days | 30 days | 30 days |
| Shard bundles | 7 days | 14 days | 30 days |

The active account plan determines the hosted retention window. If an account does not have an active subscription, Tuist uses the Air retention window. Some artifact types use shorter windows because they are expected to be regenerated.

Test attachments created before Tuist recorded a test-run identifier are excluded from automated deletion. Their files remain available while Tuist avoids an unbounded historical ownership lookup during retention cleanup.

### Self-hosted instances {#self-hosted-artifact-files}

Self-hosted artifact cleanup is opt-in, configurable separately for each artifact type, and not capped at 30 days. See the <.localized_link href="/guides/server/self-host/server#artifact-retention">self-hosted artifact retention configuration</.localized_link> for the supported artifact types and deployment options.

## Dashboard and activity data {#dashboard-and-activity-data}

Dashboard and activity records have retention policies independent of artifact-file cleanup. The windows below do not vary by hosted plan, including Enterprise.

### Xcode build and test insights {#xcode-build-and-test-insights}

Core Xcode build and test records currently have no fixed time-based deletion schedule. Other report data, such as timeline steps and machine metrics, expires separately:

| Data | Retention |
| --- | --- |
| Build summaries, per-file and per-target build records, and build issues | No fixed time-based deletion schedule |
| Test runs, module and suite results, and individual test results | No fixed time-based deletion schedule |
| Build timeline steps and their captured logs | 90 days |
| Build machine metrics | 90 days |
| Xcode project graph records | 30 days |

These records are separate from the downloadable build archives, result bundles, and test attachments covered by the [artifact-file retention windows](#hosted-artifact-files). On Enterprise, those files are retained for 30 days; the associated build and test records remain available after the files expire. A record having no fixed time-based deletion schedule is not a guarantee of permanent availability.

### Other dashboard and activity data {#other-dashboard-and-activity-data}

| Data | Retention |
| --- | --- |
| Gradle build records, task records, cache event records, Mix build records, compiled file records, build step records and diagnostics, Cargo build records (including aggregate compilation-cache measurements) and compiler observations, Bazel invocations, Bazel trace profiles, indexed profile steps and action diagnostics, pending Bazel profile and test ingestion records, Bazel invocation logs, and Bazel remote action-cache observations | 90 days |
| Xcode module compilation and cache history on persistent module detail pages | 30 days |
| Task, declared Once action, Bazel BEP action, compiled file and module observations on persistent detail pages | 90 days, except Xcode modules above |
| Persistent task/action/module/file identity metadata | 365 days without an observation |
| Runner job logs, archived runner logs, and runner job machine metrics | 90 days |
| Webhook delivery history | No fixed deletion schedule |

Persistent detail URLs do not depend on a particular build remaining available. Their identity metadata can outlive individual observations, so a detail page may have no history in the selected period. New history is indexed from reports received after the feature is deployed; existing run-level history is not retroactively copied.

ClickHouse's internal `system.*` operational log tables are configured at the ClickHouse layer rather than by Tuist's product data-retention policy. They are unbounded by default; the bundled self-hosted Docker Compose and embedded Helm ClickHouse configurations can cap them, as described under <.localized_link href="/guides/server/self-host/server#capping-operational-log-retention">capping operational log retention</.localized_link>.
