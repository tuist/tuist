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

## Report actor claim {#report-actor-claim}

Build and test report requests include the optional `x-tuist-actor-id` header only when you explicitly set `TUIST_ACTOR_ID` to an organization-scoped label or configure `tuist { buildInsights { actorId = "developer-label" } }`. The environment variable takes precedence. No label is sent by default, and the plugin does not detect operating-system usernames.

Labels must be 1–128 bytes of printable ASCII without spaces. An empty or invalid override omits the claim; set `TUIST_ACTOR_ID=""` to suppress a configured value. The label may contain personal information. Do not use credentials or other sensitive values.

The claim is unverified metadata, not authentication. Existing credentials, permissions, endpoints, and report bodies are unchanged. Servers without actor support ignore the header and keep their existing attribution; this client change alone does not add dashboard actor labels. If a custom proxy rejects unfamiliar headers, opt out using the empty environment override.

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
