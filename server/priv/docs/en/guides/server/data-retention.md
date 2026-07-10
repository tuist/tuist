---
{
  "title": "Data retention",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how long Tuist keeps downloadable artifacts and dashboard activity data."
}
---
# Data retention {#data-retention}

Tuist keeps downloadable artifacts for the windows below. Dashboard history and analytics can remain visible after artifact downloads expire. No artifact file is kept for more than 30 days.

## Artifact files {#artifact-files}

These windows define how long artifact files remain available in Tuist.

| Artifact | Air and Open Source | Pro | Enterprise |
| --- | --- | --- | --- |
| Cache artifacts, including Xcode cache, module cache, and Gradle cache files | 14 days | 30 days | 30 days |
| App preview builds and icons | 30 days | 30 days | 30 days |
| Build archives | 30 days | 30 days | 30 days |
| Run artifacts, including result bundles and session archives | 30 days | 30 days | 30 days |
| Test run attachments | 30 days | 30 days | 30 days |
| Shard bundles | 7 days | 14 days | 30 days |

The active account plan determines the retention window. If an account does not have an active subscription, Tuist uses the Air retention window. Some artifact types use shorter windows because they are expected to be regenerated.

## Dashboard and activity data {#dashboard-and-activity-data}

These windows define how long selected dashboard and activity data remains available in Tuist.

| Data | Retention |
| --- | --- |
| Xcode project graph records | 30 days |
| Gradle build records, task records, and cache event records | 90 days |
| Build machine metrics | 90 days |
| Runner job logs, archived runner logs, and runner job machine metrics | 90 days |
| Webhook delivery history | No fixed deletion schedule |

ClickHouse's internal `system.*` operational log tables are configured at the ClickHouse layer rather than by Tuist's product data-retention policy. The bundled self-hosted Docker Compose and embedded Helm ClickHouse configurations retain those operational logs for 14 days by default.
