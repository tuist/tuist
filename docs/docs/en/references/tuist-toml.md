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

## Example {#example}

```toml
project = "tuist/tuist"
url = "https://tuist.dev"
```

## Configuration precedence {#configuration-precedence}

When the same setting is defined in multiple places, Tuist resolves it using the following precedence order (highest to lowest):

1. **CLI flags**
2. **Environment variables**
3. **Tuist.swift**
4. **tuist.toml**
5. **Defaults**

