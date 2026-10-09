---
{
  "title": "Gradle Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Gradle task timings and cache behavior in the Tuist dashboard."
}
---
# Gradle build insights {#gradle-build-insights}

Tuist's Gradle plugin can send build analytics to Tuist, giving you visibility into task execution and build performance.

## Configure upload behavior {#configure-upload-behavior}

By default:
- Build analytics are uploaded in the background for local builds.
- Build analytics are uploaded in the foreground for CI runs to avoid losing telemetry on short-lived agents.

You can control this behavior using `uploadInBackground` inside the `tuist` extension:

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

## Configuration reference {#configuration-reference}

The `uploadInBackground` option is available in the `tuist` extension block in `settings.gradle.kts`:

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `uploadInBackground` | `Boolean?` | `null` (background locally, foreground on CI) | Whether to upload build insights in the background for local builds. |

This setting does not affect remote cache settings in the `buildCache` block.

## Actor attribution {#actor-attribution}

On CI, automatic detection identifies the runner's OS account (such as `runner` or `root`), not the person who triggered the build. Use an explicit identifier when needed.

The plugin reports the local username from `USER`, `USERNAME`, or `LOGNAME` when available. Set `TUIST_ACTOR_ID` to an opaque organization-wide identifier to override it, or configure `buildInsights.actorId` in your settings. The environment override takes precedence. Set either override to an empty string to omit the reported identifier; this does not remove identity established by individual credentials.

```kotlin
tuist {
    buildInsights {
        actorId = providers.environmentVariable("CORPORATE_ACTOR_ID").getOrElse("")
    }
}
```

Actor identifiers are 1–128 bytes of non-space printable ASCII. They are visible to anyone who can view the project's reports, including public viewers when the project is public, and exported with reports. Do not include secrets or personal information you do not want to publish. A verified individual credential takes precedence in the dashboard; identifiers sent by clients are otherwise explicitly **Unverified**. They never grant permissions or automatically link to a Tuist user. Old servers ignore the attribution header, and new servers continue accepting old clients without it. New shared-token reports with no identifier show **Unknown**, rather than the publishing organization; historical reports retain their prior attribution. Build and test listings separate verified-user filters from unverified reported-identifier filters.

## Network-trusted publishing {#network-trusted-publishing}

Self-hosted deployments can explicitly allow Gradle build and test reports from their trusted network without developer credentials. An operator must configure `TUIST_NETWORK_TRUSTED_REPORT_PUBLISHING=true` on the instance and restart it first. This applies to every supported project; there is no dashboard setting. See <.localized_link href="/guides/server/self-host/server#network-trusted-report-publishing">the self-hosting guide</.localized_link>.

Configure the destination once in the repository:

```kotlin
tuist {
    project = "organization/project"
    url = "https://tuist.internal.example"
    buildInsights {
        networkTrustedPublishing = true
    }
    buildCache { enabled = false }
}
```

Build and test reporting do not require authenticated cache endpoint discovery. Cache access still requires credentials: disable the cache if developers are not provisioning tokens. Unsigned test reports omit shard and existing-build references and do not drive quarantine or flakiness automations. Quarantine lookup is skipped when credentials are genuinely absent; with valid credentials, existing authenticated behavior is preserved. If credentials are present, they are still used and invalid credentials fail rather than falling back to credential-free publishing. Older servers reject credential-free reports with their normal authentication error; authenticated publishing remains compatible. Set `TUIST_NETWORK_TRUSTED_PUBLISHING=true` as an alternative client opt-in, or `false` to override the configuration and disable credential-free reporting. An explicitly empty `TUIST_TOKEN` fails closed rather than enabling credential-free publication. For fork or Dependabot jobs without secrets, remove that variable instead of defining it as an empty string.

The server assigns credential-free report IDs. Repeating a submission can create a second report; this mode does not promise idempotent retries or correlation with authenticated test reports. Such reports cannot trigger VCS comments or automatic failure-agent events. Network access is the publishing trust boundary, not proof of the reported actor's identity.

## Custom metadata {#custom-metadata}

Attach tags and key-value data to Gradle builds to compare runs from different teams, hardware, or workflows. Tags are available as dashboard filters, and values appear on each build's detail page and in the application programming interface and Model Context Protocol tools.

Set metadata with environment variables:

```sh
export TUIST_BUILD_TAGS="nightly,android"
export TUIST_BUILD_VALUE_TICKET="TUIST-123"
export TUIST_BUILD_VALUE_RUNNER="macos-14"
```

You can also configure metadata in `settings.gradle.kts`:

```kotlin
tuist {
    buildInsights {
        tag("nightly")
        tag("android")
        value("ticket", "TUIST-123")
        value("runner", "macos-14")
    }
}
```

When the same value is configured in both places, the value in `settings.gradle.kts` takes precedence.

Tags must contain only letters, numbers, hyphens, and underscores. A build can have up to 50 tags, and each tag can contain up to 50 characters. A build can have up to 20 key-value entries, each key can contain up to 50 characters, and each value can contain up to 500 characters. These are the same server-side limits used for Xcode build metadata. The plugin skips invalid tags and oversized or empty metadata entries before it sends the report, so invalid configuration cannot prevent the rest of the build insights report from being stored. Use key-value metadata for values that do not meet the tag constraint.

Custom metadata is visible to project members in the dashboard and through the application programming interface and Model Context Protocol tools. Do not use it for credentials, access tokens, or other sensitive data. Tuist retains Gradle build data, including this metadata, for 90 days. See the <.localized_link href="/guides/server/data-retention">data retention policy</.localized_link> for details.
