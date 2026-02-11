---
{
  "title": "Gradle cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Use Tuist's Gradle plugin to share build cache artifacts remotely across your team and CI environments."
}
---
# Gradle cache {#gradle-cache}

::: warning NOT GENERALLY AVAILABLE
<!-- -->
This feature is not generally available yet. If you are interested in trying it out, please reach out to us at [contact@tuist.dev](mailto:contact@tuist.dev).
<!-- -->
:::

Tuist provides a Gradle plugin that integrates with [Gradle's built-in build cache](https://docs.gradle.org/current/userguide/build_cache.html) to share build artifacts remotely. When a task's outputs are already cached, Gradle skips execution and pulls the result from Tuist's remote cache, saving build time across your team and CI environments.

## Setup {#setup}

::: warning REQUIREMENTS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Tuist account and project</LocalizedLink>
- Tuist CLI 4.138.1 or later
- A Gradle project
<!-- -->
:::

### 1. Apply the plugin {#apply-the-plugin}

Add the Tuist plugin to your `settings.gradle.kts`:

```kotlin
plugins {
    id("dev.tuist") version "0.1.0"
}
```

### 2. Configure the project {#configure-the-project}

Create a `tuist.toml` file in your project root with your project handle:

```toml
project = "your-org/your-project"
```

The Gradle plugin reads this file through the Tuist CLI, so you only need to define your project handle in one place.

### 3. Configure the plugin {#configure-the-plugin}

Add the `tuist` extension block to your `settings.gradle.kts` to configure caching behavior:

```kotlin
tuist {
    buildCache {
        enabled = true
        push = true
    }
}
```

That's it. Gradle will now use Tuist as a remote build cache. Cached task outputs are downloaded on cache hits and uploaded after task execution.

> [!NOTE]
> You can also set `project` directly in the `tuist` block in `settings.gradle.kts` instead of using `tuist.toml`. However, we recommend `tuist.toml` so the configuration is shared across Tuist CLI commands and the Gradle plugin.

### 4. Authenticate {#authenticate}

The plugin uses the Tuist CLI under the hood to obtain the session. Before running your first build, authenticate by running:

```bash
tuist auth login
```

This opens a browser-based authentication flow and stores credentials locally. The plugin then uses these credentials automatically when communicating with the remote cache. See the <LocalizedLink href="/guides/server/authentication">Authentication guide</LocalizedLink> for more details.

## Self-hosted servers {#self-hosted-servers}

If you are running a <LocalizedLink href="/guides/server/self-host/install">self-hosted Tuist server</LocalizedLink>, set the `url` in your `tuist.toml`:

```toml
project = "your-org/your-project"
url = "https://tuist.your-company.com"
```

Alternatively, you can set it in the Gradle plugin configuration:

```kotlin
tuist {
    url = "https://tuist.your-company.com"
}
```

When authenticating against a self-hosted server, pass the same URL:

```bash
tuist auth login --server https://tuist.your-company.com
```

## Cache upload policy {#cache-upload-policy}

By default, the plugin both downloads and uploads artifacts to the remote cache. You can control uploads with the `push` option in the `buildCache` block:

```kotlin
tuist {
    buildCache {
        enabled = true
        push = false // read-only mode
    }
}
```

A common pattern is to push artifacts only from CI, where builds are reproducible, while keeping local environments read-only:

```kotlin
tuist {
    buildCache {
        enabled = true
        push = System.getenv("CI") != null
    }
}
```

With this setup, local builds benefit from cached artifacts without uploading, while CI builds populate the cache for the rest of the team.

## Build insights {#build-insights}

The plugin also collects build analytics and uploads them to Tuist, giving you visibility into build performance, task execution times, and cache hit rates through the Tuist dashboard.

By default, build insights are uploaded in the background for local builds and in the foreground on CI (to make sure the upload completes before ephemeral agents exit). You can control this with the `uploadInBackground` option:

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

## Continuous integration {#continuous-integration}

To enable caching in your CI environment, make sure the Tuist CLI is installed and authenticated.

For authentication, you can use either <LocalizedLink href="/guides/server/authentication#oidc-tokens">OIDC authentication</LocalizedLink> (recommended for supported CI providers) or an <LocalizedLink href="/guides/server/authentication#account-tokens">account token</LocalizedLink> via the `TUIST_TOKEN` environment variable.

An example workflow for GitHub Actions using OIDC authentication:

```yaml
name: Build

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: ./gradlew build
```

See the <LocalizedLink href="/guides/integrations/continuous-integration">Continuous Integration guide</LocalizedLink> for more examples, including token-based authentication and other CI platforms.

## Configuration reference {#configuration-reference}

The following options are available in the `tuist` extension block in `settings.gradle.kts`:

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `project` | `String` | `""` (optional) | The project identifier in `account/project` format. If not set, the plugin reads it from `tuist.toml` via the Tuist CLI. |
| `executablePath` | `String?` | `null` (uses `tuist` from PATH) | Path to the Tuist CLI executable. |
| `url` | `String` | `"https://tuist.dev"` | The base URL of the Tuist server. Set this when using a <LocalizedLink href="/guides/server/self-host/install">self-hosted instance</LocalizedLink>. |
| `uploadInBackground` | `Boolean?` | `null` (background locally, foreground on CI) | Whether to upload build insights in the background. |

::: info TUIST.TOML
<!-- -->
The recommended way to configure `project` (and optionally `url`) is through a `tuist.toml` file in your project root. This way the configuration is shared between the Tuist CLI and the Gradle plugin. You can still override these values in `settings.gradle.kts` if needed.
<!-- -->
:::

The `buildCache` block supports:

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | Whether the remote build cache is enabled. |
| `push` | `Boolean` | `true` | Whether to upload task outputs to the remote cache. |
| `allowInsecureProtocol` | `Boolean` | `false` | Whether to allow insecure HTTP connections. |
