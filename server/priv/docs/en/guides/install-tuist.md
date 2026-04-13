---
{
  "title": "Install Tuist",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Learn how to install Tuist in your environment."
}
---
# Install Tuist {#install-tuist}

Tuist runs on **macOS** and **Linux**. Although you could manually build Tuist from [the sources](https://github.com/tuist/tuist), **we recommend using one of the following installation methods to ensure a valid installation.**

### <a href="https://github.com/jdx/mise">Mise</a> {#recommended-mise}

> [!NOTE]
> If you don't have Mise installed, follow the [getting started guide](https://mise.jdx.dev/getting-started.html) first. Mise is a recommended alternative to [Homebrew](https://brew.sh) if you are a team or organization that needs to ensure deterministic versions of tools across different environments.


Unlike tools like Homebrew, which install and activate a single version of the tool globally, **Mise pins a version** either globally or scoped to a project. Run `mise use` to install and activate Tuist:

```bash
mise use tuist@x.y.z          # Install and pin tuist-x.y.z in the current project
mise use tuist@latest          # Install and pin the latest tuist in the current project
mise use -g tuist@x.y.z       # Install and pin tuist-x.y.z as the global default
mise use -g tuist@system       # Use the system's tuist as the global default
```

If you clone a project that already has a Tuist version pinned in `mise.toml`, run `mise install` to install it.

<details>
<summary>Linux support</summary>

On Linux, Tuist is available exclusively via Mise. Commands that depend on Xcode (such as `tuist generate`) are not available on Linux, but platform-independent commands like `tuist inspect bundle` work as expected.

</details>


### <a href="https://brew.sh">Homebrew</a> (macOS only) {#recommended-homebrew}

You can install Tuist using [Homebrew](https://brew.sh) and [our formulas](https://github.com/tuist/homebrew-tuist):

```bash
brew tap tuist/tuist
brew install --formula tuist
brew install --formula tuist@x.y.z
```

> [!TIP]
> **Verifying The Authenticity Of The Binaries**
>
> You can verify that your installation's binaries have been built by us by running the following command, which checks if the certificate's team is `U6LC622NKF`:
>
> ```bash
> curl -fsSL "https://docs.tuist.dev/verify.sh" | bash
> ```

## HTTP proxy {#http-proxy}

If your network routes outbound traffic through an HTTP proxy, you can tell Tuist which proxy to use from your `Tuist.swift` manifest. Three modes are supported:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-org/my-project",

    // Choose one:
    proxy: .none,                                // default — direct connections
    proxy: .environmentVariable(),               // reads HTTPS_PROXY (default name)
    proxy: .environmentVariable("HTTP_PROXY"),   // or any other env variable
    proxy: .url("http://proxy.corp:8080"),       // hardcoded URL
    proxy: "http://proxy.corp:8080",             // shorthand — same as .url(...)

    project: .tuist()
)
```

- `.none` is the default. Tuist makes direct connections.
- `.environmentVariable()` reads the proxy URL from the named environment variable. The parameter defaults to `"HTTPS_PROXY"` to match the convention used by `curl`, `git`, and most developer tools. Pass a different name — e.g. `.environmentVariable("HTTP_PROXY")` or `.environmentVariable("CORP_PROXY")` — to read somewhere else.
- `.url("...")` uses the given URL directly. Credentials can be encoded inline as `http://user:password@proxy.corp:8080` if the proxy requires authentication. Because `Tuist.Proxy` conforms to `ExpressibleByStringLiteral`, you can also write `proxy: "http://proxy.corp:8080"` as a shorthand.

The proxy is applied as soon as Tuist loads `Tuist.swift`, so every subsequent network request Tuist makes — cache, previews, analytics, registry, etc. — goes through it.

