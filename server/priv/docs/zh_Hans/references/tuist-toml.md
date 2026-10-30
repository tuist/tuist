---
{
  "title": "tuist.toml",
  "titleTemplate": ":title · 参考文档 · Tuist",
  "description": "tuist.toml 配置文件格式的参考文档。"
}
---

# tuist.toml {#tuist-toml}

`tuist.toml` 是一个与构建系统无关的配置文件，也是 `Tuist.swift` 的演进版本。与 `Tuist.swift` 不同，它不需要 Swift，因此可以在任何平台和构建系统中使用。它非常适合没有 Swift 的环境（例如基于 Linux 的 CI 运行器），或者当你只需要配置服务器相关设置而无需完整的 `Tuist.swift` 清单时。

Tuist 会从当前工作目录向上遍历目录层次结构来查找 `tuist.toml`，并在找到第一个匹配项时停止。这意味着你可以将其放在项目根目录下，并从任何子目录运行 Tuist 命令。

## 支持的键 {#supported-keys}

| 键 | 类型 | 必需 | 默认值 | 描述 |
| --- | --- | --- | --- | --- |
| `project` | `String` | 是 | — | 项目的完整句柄（例如 `"tuist/tuist"`）。 |
| `url` | `String` | 否 | `https://tuist.dev` | Tuist 服务器的 URL。 |

### 网络 {#network}

`[network]` 表配置 Tuist 如何建立出站 HTTP 连接。

| 键 | 类型 | 必需 | 默认值 | 描述 |
| --- | --- | --- | --- | --- |
| `proxy` | `Boolean` | 否 | `true` | 当 `true` 时，如果存在由 `HTTPS_PROXY`/`HTTP_PROXY` 定义的代理，Tuist 将使用该代理。请参阅 <.localized_link href="/guides/integrations/http-proxy">HTTP 代理指南</.localized_link>。 |
| `ca_certificate` | `String` | 否 | — | PEM 或 DER 格式的 CA 证书包路径，用于在系统根证书存储之上添加信任，例如用于使用私有 CA 的自托管服务器。`TUIST_CA_CERTIFICATE` 环境变量具有更高优先级。请参阅 <.localized_link href="/cli/debugging#trusting-a-custom-ca-certificate">信任自定义 CA 证书</.localized_link>。 |

## 示例 {#example}

```toml
project = "tuist/tuist"
url = "https://tuist.dev"

[network]
proxy = true
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

## 配置优先级 {#configuration-precedence}

当同一设置在多个地方定义时，Tuist 会按照以下优先级顺序进行解析（从高到低）：

1. **CLI 标志**
2. **环境变量**
3. **Tuist.swift**
4. **tuist.toml**
5. **默认值**
