---
{
  "title": "HTTP proxy",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to configure Tuist to route outbound traffic through an HTTP proxy."
}
---
# HTTP proxy {#http-proxy}

If your network routes outbound traffic through an HTTP proxy, you can configure Tuist to route the client-side HTTP connections that it manages through that proxy.

This only affects HTTP clients created by Tuist itself, such as cache, previews, analytics, registry access, and the calls that Tuist's build-system integrations make back to Tuist services.

It does not proxy traffic from the build systems Tuist integrates with, or from your app. Configuring a Tuist proxy does not change how your build system resolves dependencies or downloads artifacts.

## Choose where to configure it {#choose-where-to-configure-it}

Choose the configuration surface based on how you integrate Tuist into your project:

| If you use... | Configure the proxy in... | Why |
| --- | --- | --- |
| Xcode projects | `Tuist.swift` | Keeps the proxy alongside the rest of your Xcode project configuration. |
| Gradle projects | `settings.gradle.kts` | Applies the proxy to the Tuist-managed HTTP clients created by the Gradle plugin. |
| Both the CLI and Gradle plugin | `tuist.toml` | Shares one proxy setting between both integrations. |

## Xcode projects {#xcode-projects}

If you use Tuist with Xcode projects, configure the proxy in your `Tuist.swift` manifest:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-org/my-project",

    // Choose one:
    proxy: .none,                                // default: direct connections
    proxy: .environmentVariable(),               // reads HTTPS_PROXY (default name)
    proxy: .environmentVariable("HTTP_PROXY"),   // or any other env variable
    proxy: .url("http://proxy.corp:8080"),       // hardcoded URL
    proxy: "http://proxy.corp:8080",             // shorthand for .url(...)

    project: .tuist()
)
```

- `.none` is the default. Tuist makes direct connections.
- `.environmentVariable()` reads the proxy URL from an environment variable at runtime. When called with no argument, Tuist reads `HTTPS_PROXY`, matching the convention used by `curl`, `git`, and most developer tools. Pass a name (for example `.environmentVariable("HTTP_PROXY")` or `.environmentVariable("CORP_PROXY")`) to read somewhere else.
- `.url("...")` uses the given URL directly. Because `Tuist.Proxy` conforms to `ExpressibleByStringLiteral`, you can also write `proxy: "http://proxy.corp:8080"` as a shorthand.

The proxy is applied as soon as Tuist loads `Tuist.swift`, so every subsequent network request Tuist makes goes through it.

## Gradle projects {#gradle-projects}

If you use the Tuist Gradle plugin, configure the proxy in `settings.gradle.kts`:

```kotlin
import dev.tuist.gradle.Proxy

tuist {
    project = "my-org/my-project"

    // Choose one:
    proxy = Proxy.None                                   // default: direct connections
    proxy = Proxy.EnvironmentVariable()                  // reads HTTPS_PROXY (default name)
    proxy = Proxy.EnvironmentVariable("HTTP_PROXY")      // or any other env variable
    proxy = Proxy.Url("http://proxy.corp:8080")          // hardcoded URL
}
```

- `Proxy.None` is the default. The plugin makes direct connections.
- `Proxy.EnvironmentVariable()` reads the proxy URL from an environment variable at runtime. When called with no argument, the plugin reads `HTTPS_PROXY`, matching the convention used by `curl`, `git`, and most developer tools. Pass a name (for example `Proxy.EnvironmentVariable("HTTP_PROXY")` or `Proxy.EnvironmentVariable("CORP_PROXY")`) to read somewhere else.
- `Proxy.Url("...")` uses the given URL directly.

The same setting applies to every HTTP client the plugin creates to talk to Tuist services: remote build cache, build insights, test insights, test quarantine, and test sharding all honor it.

It does not affect Gradle's own networking, such as dependency resolution, plugin resolution, Maven repository access, or other plugins' HTTP clients.

## Shared configuration {#tuist-toml}

If you want the same proxy to apply to both the Tuist CLI and the Gradle plugin, define it once in `tuist.toml`:

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

The `[proxy]` table must contain exactly one of:

- `url`
- `environment_variable`

Setting both keys, or neither, is a configuration error.

This shared configuration is still limited to Tuist-managed client connections. It does not become a global system or Gradle-wide proxy setting.

## Precedence {#precedence}

When multiple configuration surfaces are present, Tuist uses the following precedence:

- Xcode projects: `Tuist.swift` overrides `tuist.toml`.
- Gradle projects: `proxy` in the `tuist {}` extension overrides `tuist.toml`.
- `tuist.toml` is the shared fallback when you want both integrations to use the same proxy.

## Related guides {#related-guides}

- <.localized_link href="/guides/install-tuist">Install Tuist</.localized_link>
- <.localized_link href="/guides/install-gradle-plugin">Install the Gradle plugin</.localized_link>
