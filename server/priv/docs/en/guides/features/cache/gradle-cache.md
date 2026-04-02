---
{
  "title": "Gradle cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Share Gradle build cache artifacts across your team and CI with Tuist."
}
---
# Gradle cache {#gradle-cache}

Tuist provides a Gradle plugin that integrates with [Gradle's built-in build cache](https://docs.gradle.org/current/userguide/build_cache.html) to share build artifacts remotely. When a task's outputs are already cached, Gradle skips execution and pulls the result from Tuist's remote cache, saving build time across your team and CI environments.

> [!WARNING]
> **Requirements**
>
> - The <TuistWeb.Docs.MarkdownComponents.localized_link href="/guides/install-gradle-plugin">Tuist Gradle plugin</TuistWeb.Docs.MarkdownComponents.localized_link> installed and configured


Once the <TuistWeb.Docs.MarkdownComponents.localized_link href="/guides/install-gradle-plugin">Tuist Gradle plugin</TuistWeb.Docs.MarkdownComponents.localized_link> is installed, you also need to enable Gradle's build cache in your `gradle.properties` file:

```properties
org.gradle.caching=true
```

Without this, Gradle does not activate its build cache subsystem — even with a remote cache configured — and all tasks will execute without hitting or populating the cache. Once enabled, Gradle will use Tuist as a remote build cache, downloading cached task outputs on cache hits and uploading them after task execution.

## Cache upload policy {#cache-upload-policy}

By default, the plugin both downloads and uploads artifacts to the remote cache. You can control uploads with the `push` option in the `buildCache` block:

```kotlin
tuist {
    buildCache {
        push = false // read-only mode
    }
}
```

A common pattern is to push artifacts only from CI, where builds are reproducible, while keeping local environments read-only:

```kotlin
tuist {
    buildCache {
        push = System.getenv("CI") != null
    }
}
```

With this setup, local builds benefit from cached artifacts without uploading, while CI builds populate the cache for the rest of the team.

## Continuous integration {#continuous-integration}

For CI environments, authenticate using one of the methods in the <TuistWeb.Docs.MarkdownComponents.localized_link href="/guides/server/authentication#continuous-integration">Authentication guide</TuistWeb.Docs.MarkdownComponents.localized_link>.
See the <TuistWeb.Docs.MarkdownComponents.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</TuistWeb.Docs.MarkdownComponents.localized_link> for provider-specific CI examples.

### Disabling the local build cache {#disabling-the-local-build-cache}

Gradle maintains both a local and a remote build cache. The local build cache stores task outputs on disk under `~/.gradle/caches/build-cache-1`.

When Tuist is configured as the remote build cache, it is recommended to disable the local build cache on CI. This avoids storing redundant artifacts on CI runners and ensures builds always populate the remote cache with fresh entries for the rest of the team.

Disable Gradle's local build cache on CI in your `settings.gradle.kts`:

```kotlin
buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}
```

This keeps the local build cache available for local development while disabling it on CI, where Tuist's remote cache handles artifact sharing.

## Configuration reference {#configuration-reference}

The `buildCache` block supports:

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | Whether the remote build cache is enabled. |
| `push` | `Boolean` | `true` | Whether to upload task outputs to the remote cache. |
| `allowInsecureProtocol` | `Boolean` | `false` | Whether to allow insecure HTTP connections. |
