---
{
  "title": "Install the Gradle plugin",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Learn how to install and configure Tuist's Gradle plugin in your project."
}
---
# Install the Gradle plugin {#install-the-gradle-plugin}

Tuist provides a Gradle plugin that integrates with your Gradle project to enable features like <.localized_link href="/guides/features/cache/gradle-cache">remote build caching</.localized_link> and <.localized_link href="/guides/features/build-insights/gradle">build insights</.localized_link>. This guide walks you through installing and configuring the plugin.

> [!WARNING]
> **Requirements**
>
> - <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> 4.138.1 or later
> - A Gradle project


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

For CI, follow the <.localized_link href="/guides/integrations/continuous-integration#authentication">CI authentication guide</.localized_link> to configure authentication for your environment.

## Configuration reference {#configuration-reference}

The following options are available in the `tuist` extension block in `settings.gradle.kts`:

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `project` | `String?` | `null` (optional) | The project identifier in `account/project` format. If not set, the plugin reads it from `tuist.toml` through the Tuist CLI. |
| `executablePath` | `String?` | `null` (uses `tuist` from PATH) | Path to the Tuist CLI executable. |
| `url` | `String?` | `null` | The base URL of the Tuist server. If not set, it defaults to `"https://tuist.dev"` or the value defined in `tuist.toml`. |
| `uploadInBackground` | `Boolean?` | `null` | Whether to upload build and test insights in the background. When `null` (default), uploads run in the background for local builds and in the foreground on CI. |
| `proxy` | `Proxy` | `Proxy.None` | The HTTP proxy the plugin routes its traffic through. See [HTTP proxy](#http-proxy). |

> [!NOTE]
> **Tuist.toml**
>
> The recommended way to configure `project` (and optionally `url`) is through a `tuist.toml` file in your project root. This way the configuration is shared between the Tuist CLI and the Gradle plugin. You can still override these values in `settings.gradle.kts` if needed.

## HTTP proxy {#http-proxy}

If your network routes outbound traffic through an HTTP proxy, you can tell the Gradle plugin which proxy to use via the `proxy` option. The same setting applies to every HTTP client the plugin creates — the remote build cache, build insights, test insights, test quarantine, and test sharding all honor it.

Three modes are supported:

```kotlin
import dev.tuist.gradle.Proxy

tuist {
    project = "my-org/my-project"

    // Choose one:
    proxy = Proxy.None                                   // default — direct connections
    proxy = Proxy.EnvironmentVariable()                  // reads HTTPS_PROXY (default name)
    proxy = Proxy.EnvironmentVariable("HTTP_PROXY")      // or any other env variable
    proxy = Proxy.Url("http://proxy.corp:8080")          // hardcoded URL
}
```

- `Proxy.None` is the default. The plugin makes direct connections.
- `Proxy.EnvironmentVariable()` reads the proxy URL from the named environment variable. The parameter defaults to `"HTTPS_PROXY"` to match the convention used by `curl`, `git`, and most developer tools. Pass a different name — e.g. `Proxy.EnvironmentVariable("HTTP_PROXY")` or `Proxy.EnvironmentVariable("CORP_PROXY")` — to read somewhere else.
- `Proxy.Url("...")` uses the given URL directly. Credentials can be encoded inline as `http://user:password@proxy.corp:8080` if the proxy requires authentication.

Proxy resolution happens at configure time, so the environment variables you reference must be set when Gradle evaluates `settings.gradle.kts`. On CI that means exporting them in the same job that invokes Gradle.

### Configuring the proxy from `tuist.toml` {#http-proxy-toml}

The proxy can also live in `tuist.toml` alongside `project` and `url`, which keeps the setting in sync with the Tuist CLI (so both tools go through the same proxy). Add a `[proxy]` table with exactly one key:

```toml
project = "my-org/my-project"

[proxy]
url = "http://proxy.corp:8080"
```

or

```toml
project = "my-org/my-project"

[proxy]
environment_variable = "HTTPS_PROXY"
```

When the `proxy` value on the `tuist` extension is left at its default (`Proxy.None`), the Gradle plugin falls back to the `[proxy]` table in `tuist.toml`. Setting `proxy` on the extension explicitly overrides anything in `tuist.toml`.


## Next steps {#next-steps}

Once the plugin is installed and configured, you can enable:

- <.localized_link href="/guides/features/cache/gradle-cache">Remote build cache</.localized_link> to share build artifacts across your team and CI.
- <.localized_link href="/guides/features/build-insights/gradle">Build insights</.localized_link> to track task timings and cache behavior in the Tuist dashboard.
- <.localized_link href="/guides/features/test-insights/gradle">Test insights</.localized_link> to track test performance and detect flaky tests.
- <.localized_link href="/guides/features/test-insights/flaky-tests">Flaky tests</.localized_link> to automatically detect, track, and quarantine flaky tests.
