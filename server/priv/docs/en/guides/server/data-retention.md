---
{
  "title": "Data retention",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how long Tuist keeps downloadable artifacts and dashboard activity data."
}
---
# Data retention {#data-retention}

Tuist Cloud and self-hosted Tuist instances apply different artifact-retention policies. Tuist Cloud uses plan-based windows capped at 30 days. Artifact cleanup is disabled by default on self-hosted instances, where operators can opt in and configure a separate window for each supported artifact type.

## Artifact files {#artifact-files}

### Tuist Cloud {#tuist-cloud-artifact-files}

These windows define how long artifact files remain available in Tuist Cloud.

| Artifact | Air and Open Source | Pro | Enterprise |
| --- | --- | --- | --- |
| Cache artifacts, including Xcode cache, module cache, and Gradle cache files | 14 days | 30 days | 30 days |
| App preview builds and icons | 30 days | 30 days | 30 days |
| Build archives | 30 days | 30 days | 30 days |
| Run artifacts, including result bundles and session archives | 30 days | 30 days | 30 days |
| Test run attachments | 30 days | 30 days | 30 days |
| Shard bundles | 7 days | 14 days | 30 days |

The active account plan determines the Tuist Cloud retention window. If an account does not have an active subscription, Tuist uses the Air retention window. Some artifact types use shorter windows because they are expected to be regenerated.

### Self-hosted instances {#self-hosted-artifact-files}

Self-hosted artifact cleanup is opt-in and configured separately for each artifact type. Set an artifact type's environment variable to a positive integer number of days to enable its cleanup. Leaving a variable unset or blank disables cleanup only for that artifact type. Self-hosted windows are not capped at 30 days.

The following example enables every supported artifact type with an independent retention window. Omit a variable or leave it blank to keep cleanup disabled for that artifact type.

```bash
TUIST_CACHE_ARTIFACT_RETENTION_DAYS=30
TUIST_APP_PREVIEW_RETENTION_DAYS=30
TUIST_BUILD_ARCHIVE_RETENTION_DAYS=60
TUIST_RUN_ARTIFACT_RETENTION_DAYS=30
TUIST_TEST_ATTACHMENT_RETENTION_DAYS=30
TUIST_SHARD_BUNDLE_RETENTION_DAYS=14
```

The supported variables and their object-storage scope are:

| Environment variable | Artifact files |
| --- | --- |
| `TUIST_CACHE_ARTIFACT_RETENTION_DAYS` | Xcode cache, legacy content-addressable storage cache, module cache, and Gradle cache files |
| `TUIST_APP_PREVIEW_RETENTION_DAYS` | App preview builds and icons |
| `TUIST_BUILD_ARCHIVE_RETENTION_DAYS` | Current and legacy build archives |
| `TUIST_RUN_ARTIFACT_RETENTION_DAYS` | All objects stored under an expired run's artifact prefix, including result bundles, invocation records, and session archives |
| `TUIST_TEST_ATTACHMENT_RETENTION_DAYS` | Test run attachments |
| `TUIST_SHARD_BUNDLE_RETENTION_DAYS` | Test shard bundles |

The cleanup jobs remove artifact blobs from object storage only. Associated PostgreSQL and ClickHouse metadata remains available for analytics and dashboards. The setting does not change database retention rules.

Cache artifact cleanup scans the instance-managed cache buckets and skips accounts configured with account-specific custom cache storage. Matching cache objects whose prefix no longer resolves to a current account are cleaned with the configured window. Database-backed cleanup for app previews, current build archives, run artifacts, test attachments, and shard bundles uses the account's current storage configuration. Legacy build archive cleanup scans the instance-managed artifact bucket. Package registry mirror objects and runner log archives are outside this configurable policy. Runner log archives keep their separate 90-day retention window.

See the <.localized_link href="/guides/server/self-host/server#artifact-retention">self-hosted artifact retention configuration</.localized_link> for deployment details. These variables do not override the Tuist Cloud plan-based windows.

## Dashboard and activity data {#dashboard-and-activity-data}

These windows define how long selected dashboard and activity data remains available in Tuist. They are independent of the configurable self-hosted artifact cleanup above.

| Data | Retention |
| --- | --- |
| Xcode project graph records | 30 days |
| Gradle build records, task records, and cache event records | 90 days |
| Build machine metrics | 90 days |
| Runner job logs, archived runner logs, and runner job machine metrics | 90 days |
| Webhook delivery history | No fixed deletion schedule |
