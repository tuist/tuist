---
{
  "title": "Install the Gradle plugin",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Learn how to install and configure Tuist's Gradle plugin in your project."
}
---
# Install the Gradle plugin {#install-the-gradle-plugin}

::: warning NOT GENERALLY AVAILABLE
<!-- -->
This feature is not generally available yet. If you are interested in trying it out, please reach out to us at [contact@tuist.dev](mailto:contact@tuist.dev).
<!-- -->
:::

Tuist provides a Gradle plugin that integrates with your Gradle project to enable features like <LocalizedLink href="/guides/features/cache/gradle-cache">remote build caching</LocalizedLink> and <LocalizedLink href="/guides/features/insights/gradle-cache">build insights</LocalizedLink>. This guide walks you through installing and configuring the plugin.

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist account and project</LocalizedLink>
- Tuist CLI 4.138.1 or later
- A Gradle project
<!-- -->
:::

## 1. Apply the plugin {#apply-the-plugin}

Add the Tuist plugin to your `settings.gradle.kts`:

```kotlin
plugins {
    id("dev.tuist") version "0.1.0"
}
```

## 2. Configure the project {#configure-the-project}

Create a `tuist.toml` file in your project root with your project handle:

```toml
project = "your-org/your-project" # Optional: can be set here or in settings.gradle.kts
```

The Gradle plugin reads this file through the Tuist CLI, so you only need to define your project handle in one place. If `project` is not set in `settings.gradle.kts`, the plugin falls back to `tuist.toml`.

> [!NOTE]
> You can also set `project` directly in the `tuist` block in `settings.gradle.kts` instead of using `tuist.toml`. However, we recommend `tuist.toml` so the configuration is shared across Tuist CLI commands and the Gradle plugin.

## 3. Authenticate {#authenticate}

The plugin uses the Tuist CLI authentication flow and reads credentials from the same sources as other Tuist tooling. Follow <LocalizedLink href="/guides/server/authentication#gradle-plugin-authentication">Gradle plugin authentication</LocalizedLink> for setup details.

## Self-hosted servers {#self-hosted-servers}

If you are running a <LocalizedLink href="/guides/server/self-host/install">self-hosted Tuist server</LocalizedLink>, set the `url` in your `tuist.toml`:

```toml
project = "your-org/your-project"
url = "https://tuist.your-company.com"
```

## Configuration reference {#configuration-reference}

The following options are available in the `tuist` extension block in `settings.gradle.kts`:

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (optional) | The project identifier in `account/project` format. If not set, the plugin reads it from `tuist.toml` through the Tuist CLI. |
| `executablePath` | `String?` | `null` (uses `tuist` from PATH) | Path to the Tuist CLI executable. |
| `url` | `String?` | `null` | The base URL of the Tuist server. If not set, it defaults to `"https://tuist.dev"` or the value defined in `tuist.toml`. |

::: info TUIST.TOML
<!-- -->
The recommended way to configure `project` (and optionally `url`) is through a `tuist.toml` file in your project root. This way the configuration is shared between the Tuist CLI and the Gradle plugin. You can still override these values in `settings.gradle.kts` if needed.
<!-- -->
:::

## Next steps {#next-steps}

Once the plugin is installed and configured, you can enable:

- <LocalizedLink href="/guides/features/cache/gradle-cache">Gradle remote build cache</LocalizedLink> to share build artifacts across your team and CI.
- <LocalizedLink href="/guides/features/insights/gradle-cache">Gradle build insights</LocalizedLink> to track task timings and cache behavior in the Tuist dashboard.
