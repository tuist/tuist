---
{
  "title": "Gradle Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track Gradle task timings and cache behavior in the Tuist dashboard."
}
---
# Gradle build insights {#gradle-build-insights}

> [!WARNING]
> **Requirements**
>
> - The <.localized_link href="/guides/install-gradle-plugin">Tuist Gradle plugin</.localized_link> installed and configured


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

## Custom metadata {#custom-metadata}

Attach tags and key-value data to Gradle builds to compare runs from different teams, hardware, or workflows. Tags are available as dashboard filters, and values appear on each build's detail page and in the application programming interface and Model Context Protocol tools.

The plugin collects these values automatically when they are available:

| Key | Description |
| --- | --- |
| `os_name` | Operating system name. |
| `os_version` | Operating system version. |
| `os_architecture` | Machine architecture reported by the Java runtime. |
| `cpu_model` | Processor model. |
| `cpu_cores` | Number of processors available to the Java runtime. |
| `memory_total_bytes` | Total system memory in bytes. |
| `power_source` | `ac` or `battery` when the platform exposes its power state. |

Set additional metadata with environment variables. Values from the Gradle configuration take precedence over environment variables, and both take precedence over automatically collected values with the same key.

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

### Use with the Gradle Common Custom User Data plugin {#common-custom-user-data}

Tuist recognizes the [Gradle Common Custom User Data plugin](https://github.com/gradle/common-custom-user-data-gradle-plugin) when both plugins are applied in `settings.gradle.kts`. It independently records normalized equivalents of the common data that plugin adds to Develocity build scans, so the data is available in Tuist even though Develocity build scan metadata is not readable by Tuist.

```kotlin
plugins {
    id("com.gradle.develocity") version "<develocity-version>"
    id("com.gradle.common-custom-user-data-gradle-plugin") version "<common-custom-user-data-version>"
    id("dev.tuist") version "<tuist-version>"
}
```

When the Common Custom User Data plugin is present, Tuist adds normalized tags for the operating system, local or continuous-integration invocation, detected continuous-integration provider, integrated development environment or command-line invocation, checkout state, and supported coding agents. It adds values such as `invocation_source`, `ide_version`, `ci_provider`, `ci_build_url`, `ci_build_number`, `ci_job`, `ci_workflow`, `ci_stage`, `ci_node`, `git_dirty`, and `ai_agent` when available.

Tuist already reports the Git branch, revision, reference, and remote URL in the build record. For checkout state it reports only the `git_dirty` value and `dirty` tag; it does not upload the raw Git status because it may disclose file paths.

Tags must contain only letters, numbers, hyphens, and underscores. A build can have up to 50 tags, and each tag can contain up to 50 characters. A build can have up to 20 key-value entries, each key can contain up to 50 characters, and each value can contain up to 500 characters. These are the same server-side limits used for Xcode build metadata. The plugin skips invalid tags and oversized or empty metadata entries before it sends the report, so invalid configuration cannot prevent the rest of the build insights report from being stored. Use key-value metadata for values that do not meet the tag constraint.

Automatic machine, invocation, and continuous-integration metadata is enabled by default. Disable it when your project must limit metadata collection, while continuing to send the tags and values you configure explicitly:

```kotlin
tuist {
    buildInsights {
    }
}
```

Custom metadata is visible to project members in the dashboard and through the application programming interface and Model Context Protocol tools. Do not use it for credentials, access tokens, or other sensitive data. Tuist retains Gradle build data, including this metadata, for 90 days. See the <.localized_link href="/guides/server/data-retention">data retention policy</.localized_link> for details.
