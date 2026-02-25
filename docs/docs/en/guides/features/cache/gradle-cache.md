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

::: warning REQUIREMENTS
<!-- -->
- The <LocalizedLink href="/guides/install-gradle-plugin">Tuist Gradle plugin</LocalizedLink> installed and configured
<!-- -->
:::

Once the <LocalizedLink href="/guides/install-gradle-plugin">Tuist Gradle plugin</LocalizedLink> is installed, you also need to enable Gradle's build cache in your `gradle.properties` file:

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

For CI environments, authenticate using one of the methods in the <LocalizedLink href="/guides/server/authentication#continuous-integration">Authentication guide</LocalizedLink>.
See the <LocalizedLink href="/guides/integrations/continuous-integration">Continuous Integration guide</LocalizedLink> for provider-specific CI examples.

## Configuration reference {#configuration-reference}

The `buildCache` block supports:

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | `Boolean` | `true` | Whether the remote build cache is enabled. |
| `push` | `Boolean` | `true` | Whether to upload task outputs to the remote cache. |
| `allowInsecureProtocol` | `Boolean` | `false` | Whether to allow insecure HTTP connections. |
