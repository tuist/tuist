---
{
  "title": "tuist.toml",
  "titleTemplate": ":title · References · Tuist",
  "description": "Reference for the tuist.toml configuration file format."
}
---

# tuist.toml {#tuist-toml}

`tuist.toml` is a build-system agnostic configuration file and an evolution of `Tuist.swift`. Unlike `Tuist.swift`, it does not require Swift, making it usable across any platform and build system. It is ideal for environments where Swift is not available, such as Linux-based CI runners, or when you only need to configure server-related settings without a full `Tuist.swift` manifest.

Tuist looks for `tuist.toml` by traversing the directory hierarchy upward from the current working directory, stopping at the first match. This means you can place it at the root of your project and run Tuist commands from any subdirectory.

## Supported keys {#supported-keys}

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `project` | `String` | Yes | — | The full handle of your project (e.g. `"tuist/tuist"`). |
| `url` | `String` | No | `https://tuist.dev` | The URL of the Tuist server. |

### Network {#network}

The `[network]` table configures how Tuist makes outbound HTTP connections.

| Key | Type | Required | Default | Description |
| --- | --- | --- | --- | --- |
| `proxy` | `Boolean` | No | `true` | When `true`, Tuist uses the proxy defined by `HTTPS_PROXY`/`HTTP_PROXY` when present. See the <.localized_link href="/guides/integrations/http-proxy">HTTP proxy guide</.localized_link>. |
| `caCertificate` | `String` | No | — | Path to a PEM or DER CA certificate bundle to trust on top of the system root store, for example for a self-hosted server that uses a private CA. The `TUIST_CA_CERTIFICATE` environment variable takes precedence. See <.localized_link href="/cli/debugging#trusting-a-custom-ca-certificate">trusting a custom CA certificate</.localized_link>. |

## Example {#example}

```toml
project = "tuist/tuist"
url = "https://tuist.dev"

[network]
proxy = true
caCertificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

## Configuration precedence {#configuration-precedence}

When the same setting is defined in multiple places, Tuist resolves it using the following precedence order (highest to lowest):

1. **CLI flags**
2. **Environment variables**
3. **Tuist.swift**
4. **tuist.toml**
5. **Defaults**

