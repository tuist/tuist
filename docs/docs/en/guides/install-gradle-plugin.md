---
{
  "title": "Install the Gradle plugin",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Learn how to install and configure Tuist's Gradle plugin in your project."
}
---
# Install the Gradle plugin {#install-the-gradle-plugin}

Tuist provides a Gradle plugin that integrates with your Gradle project to enable features like <LocalizedLink href="/guides/features/cache/gradle-cache">remote build caching</LocalizedLink> and <LocalizedLink href="/guides/features/insights/gradle-cache">build insights</LocalizedLink>. This guide walks you through installing and configuring the plugin.

::: warning REQUIREMENTS
<!-- -->
- <LocalizedLink href="/guides/install-tuist">Tuist CLI</LocalizedLink> 4.138.1 or later
- A Gradle project
<!-- -->
:::

## 1. Initialize Tuist {#initialize-tuist}

Run the following command in your Gradle project root:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

The command will walk you through authenticating, creating or selecting a Tuist project, and generating the configuration for your Gradle project.

## 2. Apply the plugin {#apply-the-plugin}

After running `tuist init`, you'll need to add the Tuist plugin to your `settings.gradle.kts` as instructed by the command output:

```kotlin
plugins {
    id("dev.tuist") version "0.1.0"
}
```

## 3. Authenticate your team and CI {#authenticate}

While `tuist init` authenticates you locally, your teammates and CI environments will need to authenticate separately.

Each teammate should run the following to get access to the Tuist features on their machine:

```bash
tuist auth login
```

For CI, follow the <LocalizedLink href="/guides/integrations/continuous-integration#authentication">CI authentication guide</LocalizedLink> to configure authentication for your environment.

## Configuration reference {#configuration-reference}

The following options are available in the `tuist` extension block in `settings.gradle.kts`:

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (optional) | The project identifier in `account/project` format. If not set, the plugin reads it from `tuist.toml` through the Tuist CLI. |
| `executablePath` | `String?` | `null` (uses `tuist` from PATH) | Path to the Tuist CLI executable. |
| `url` | `String?` | `null` | The base URL of the Tuist server. If not set, it defaults to `"https://tuist.dev"` or the value defined in `tuist.toml`. |
| `uploadInBackground` | `Boolean?` | `null` | Whether to upload build and test insights in the background. When `null` (default), uploads run in the background for local builds and in the foreground on CI. |

::: info TUIST.TOML
<!-- -->
The recommended way to configure `project` (and optionally `url`) is through a `tuist.toml` file in your project root. This way the configuration is shared between the Tuist CLI and the Gradle plugin. You can still override these values in `settings.gradle.kts` if needed.
<!-- -->
:::

## Next steps {#next-steps}

Once the plugin is installed and configured, you can enable:

- <LocalizedLink href="/guides/features/cache/gradle-cache">Remote build cache</LocalizedLink> to share build artifacts across your team and CI.
- <LocalizedLink href="/guides/features/insights/gradle-cache">Build insights</LocalizedLink> to track task timings and cache behavior in the Tuist dashboard.
- <LocalizedLink href="/guides/features/test-insights/gradle">Test insights</LocalizedLink> to track test performance and detect flaky tests.
- <LocalizedLink href="/guides/features/test-insights/flaky-tests">Flaky tests</LocalizedLink> to automatically detect, track, and quarantine flaky tests.
