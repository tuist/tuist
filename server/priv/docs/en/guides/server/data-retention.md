---
{
  "title": "Data retention",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how long Tuist keeps downloadable artifacts and dashboard activity data."
}
---
# Data retention {#data-retention}

The hosted Tuist server and self-hosted Tuist instances apply different artifact-retention policies. The hosted server uses plan-based windows capped at 30 days. Artifact cleanup is disabled by default on self-hosted instances, where operators can opt in and configure a separate window for each supported artifact type.

## Artifact files {#artifact-files}

### Hosted Tuist server {#hosted-artifact-files}

These windows define how long artifact files remain available on the hosted Tuist server.

| Artifact | Air and Open Source | Pro | Enterprise |
| --- | --- | --- | --- |
| Cache artifacts, including Xcode cache, module cache, and Gradle cache files | 14 days | 30 days | 30 days |
| App preview builds and icons | 30 days | 30 days | 30 days |
| Build archives | 30 days | 30 days | 30 days |
| Run artifacts, including result bundles and session archives | 30 days | 30 days | 30 days |
| Test run attachments | 30 days | 30 days | 30 days |
| Shard bundles | 7 days | 14 days | 30 days |

The active account plan determines the hosted retention window. If an account does not have an active subscription, Tuist uses the Air retention window. Some artifact types use shorter windows because they are expected to be regenerated.

### Self-hosted instances {#self-hosted-artifact-files}

Self-hosted artifact cleanup is opt-in, configurable separately for each artifact type, and not capped at 30 days. See the <.localized_link href="/guides/server/self-host/server#artifact-retention">self-hosted artifact retention configuration</.localized_link> for the supported artifact types and deployment options.

## Dashboard and activity data {#dashboard-and-activity-data}

These windows define how long selected dashboard and activity data remains available in Tuist. They are independent of the configurable self-hosted artifact cleanup above.

| Data | Retention |
| --- | --- |
| Xcode project graph records | 30 days |
| Gradle build records, task records, and cache event records | 90 days |
| Build machine metrics | 90 days |
| Runner job logs, archived runner logs, and runner job machine metrics | 90 days |
| Webhook delivery history | No fixed deletion schedule |
