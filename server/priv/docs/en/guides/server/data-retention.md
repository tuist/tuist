---
{
  "title": "Data retention",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how long Tuist keeps artifact files, analytics records, runner logs, and runner metrics."
}
---
# Data retention {#data-retention}

Tuist keeps product metadata so dashboards and analytics continue to work over time, while large artifact files are removed after the retention window for the account's plan. No artifact file is kept for more than 30 days.

## Artifact files {#artifact-files}

Artifact retention applies to uploaded files and generated archives stored by Tuist. The cleanup process runs daily. Once a file is older than its retention window, Tuist removes it from object storage. The related metadata, such as build runs, test runs, command events, preview records, and shard plans, remains available for dashboards and analytics.

| Artifact | Air and Open Source | Pro | Enterprise |
| --- | --- | --- | --- |
| Cache artifacts, including Xcode cache, module cache, and Gradle cache files | 14 days | 30 days | 30 days |
| App preview builds and icons | 30 days | 30 days | 30 days |
| Build archives | 30 days | 30 days | 30 days |
| Run artifacts, including result bundles and session archives | 30 days | 30 days | 30 days |
| Test run attachments | 30 days | 30 days | 30 days |
| Shard bundles | 7 days | 14 days | 30 days |

The active account plan determines the retention window. If an account does not have an active subscription, Tuist uses the Air retention window. Some artifact types have shorter retention windows when they are cheap to regenerate.

## Operational records {#operational-records}

Some operational records expire independently from artifact files:

| Data | Retention |
| --- | --- |
| Xcode project graph records | 30 days |
| Gradle build records, task records, and cache event records | 90 days |
| Build machine metrics | 90 days |
| Runner job logs, archived runner logs, and runner job machine metrics | 90 days |

Webhook delivery attempts are kept without a fixed retention window because they are customer-facing audit records for debugging deliveries.

## Exports {#exports}

Data exports include the files and records that are still present when the export runs. Files that have already been removed by the retention process are no longer available in exports, but their related metadata can still be included when Tuist keeps that metadata for dashboards and analytics.
