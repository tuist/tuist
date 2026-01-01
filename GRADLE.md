# Gradle Support

This document captures the design decisions behind Tuist's Gradle integration.

## Architecture

### Server Components

The Gradle cache is implemented on the server side with:

1. **Database**: Projects have a `build_system` column (enum: `xcode`, `gradle`) to identify the toolchain.

2. **API Endpoint**: `GET/PUT /api/cache/gradle/:account_handle/:project_handle/:hash`
   - Implements Gradle's HTTP build cache protocol
   - Uses HTTP Basic Auth with account tokens
   - Stores artifacts in S3 at `{account}/{project}/gradle/{hash}`

3. **Authentication**: Uses existing account tokens with `project:cache:read` and `project:cache:write` scopes.

### Storage Path

Gradle cache artifacts are stored at:
```
{account_name}/{project_name}/gradle/{cache_key}
```

This follows the same pattern as other cache types (CAS, module cache).

## Initial Implementation

The first version uses a simple, static configuration approach:

### Configuration

Users configure Gradle's built-in `HttpBuildCache` in their `settings.gradle.kts`:

```kotlin
buildCache {
    remote<HttpBuildCache> {
        url = uri("https://tuist.dev/api/cache/gradle/{account-handle}/{project-handle}/")
        credentials {
            username = "token"
            password = providers.environmentVariable("TUIST_TOKEN").get()
        }
        isPush = true
    }
}
```

### Authentication

Users generate an account token through the Tuist CLI:

```bash
tuist account tokens create {account-handle} \
  --scopes project:cache:read \
  --scopes project:cache:write \
  --name gradle-cache
```

This outputs a token that should be stored securely (e.g., in an environment variable or CI secret).

### Local Development

For local testing against the dev server:

```kotlin
buildCache {
    remote<HttpBuildCache> {
        url = uri("http://localhost:8080/api/cache/gradle/tuist/gradle/")
        credentials {
            username = "token"
            password = System.getenv("TUIST_TOKEN") ?: ""
        }
        isPush = true
        isAllowUntrustedServer = true
    }
}
```

Run the seed script to create a test project and token:
```bash
mix run priv/repo/seeds.exs
```

The seed creates:
- Project: `tuist/gradle` with `build_system: :gradle`
- Token: `tuist_{id}_gradlecachedevtoken` with cache read/write scopes

## Future: Plugin-Based Dynamic Resolution

A future version will introduce a Gradle settings plugin (`dev.tuist`) that handles dynamic endpoint resolution and authentication automatically.

### Why a Plugin Will Be Needed

Gradle's built-in `HttpBuildCache` requires a static URL configured in `settings.gradle.kts`. To support dynamic endpoint resolution (routing to optimal cache nodes based on location or load), we need a plugin.

### The Configuration Cache Problem

Gradle's configuration cache aggressively caches values computed during settings evaluation. If you use `providers.exec()` to call a CLI command, Gradle treats the output as a configuration cache input and reuses it across builds:

```kotlin
// This gets cached - won't re-run on subsequent builds
val cacheUrl = providers.exec {
    commandLine("tuist", "cache", "endpoint")
}.standardOutput.asText.get()
```

There is no way to disable configuration caching for a specific provider. A settings plugin can bypass this by using `ProcessBuilder` directly during `settingsEvaluated`, giving fresh endpoint resolution on every build.

### Planned CLI Commands

The plugin will shell out to:

- `tuist cache endpoint` - returns the optimal cache node URL
- `tuist cache token` - returns the authentication token

Both commands will support `--json` for structured output.
