---
{
  "title": "安装 Gradle 插件",
  "titleTemplate": ":title · 指南 · Tuist",
  "description": "了解如何在项目中安装和配置 Tuist 的 Gradle 插件。"
}
---
# 安装 Gradle 插件 {#install-the-gradle-plugin}

Tuist 提供了一个 Gradle 插件，可与你的 Gradle 项目集成，以启用<.localized_link href="/guides/features/cache/gradle-cache">远程构建缓存</.localized_link>和<.localized_link href="/guides/features/build-insights/gradle">构建洞察</.localized_link>等功能。本指南将引导你完成插件的安装和配置。

该插件需要 Gradle 8.12.1 或更高版本。

## 1. 初始化 Tuist {#initialize-tuist}

在你的 Gradle 项目根目录中运行以下命令：

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

该命令将引导你完成身份验证、创建或选择 Tuist 项目，并为你的 Gradle 项目生成配置。

## 2. 应用插件 {#apply-the-plugin}

运行 `tuist init` 后，你需要按照命令输出的指示，将 Tuist 插件添加到 `settings.gradle.kts` 中：

```kotlin
plugins {
    id("dev.tuist") version "0.10.0"
}
```

## 3. 为你的团队和持续集成进行身份验证 {#authenticate}

虽然 `tuist init` 会在本地对你进行身份验证，但你的团队成员和 <.localized_link href="/guides/integrations/continuous-integration">持续集成</.localized_link> 环境需要单独进行身份验证。

每位团队成员都应运行以下命令，以便在其机器上访问 Tuist 功能：

```bash
tuist auth login
```

当你使用自托管或本地 Tuist 服务器时，请传入在 `tuist.toml` 中配置的相同基础 URL：

```bash
tuist auth login --url http://localhost:8080
tuist auth whoami --url http://localhost:8080
```

保持主机名拼写一致。例如，为 `localhost` 存储的登录信息与为 `127.0.0.1` 存储的登录信息是分开的。

对于自动化运行器，请遵循 <.localized_link href="/guides/integrations/continuous-integration#authentication">持续集成身份验证指南</.localized_link> 来为你的环境配置身份验证。

## 配置缓存和隔离项目 {#configuration-cache-and-isolated-projects}

该插件支持 Gradle 的配置缓存和[隔离项目](https://docs.gradle.org/current/userguide/isolated_projects.html)。将插件保留在 `settings.gradle.kts` 中；你无需在每个子项目中单独应用它。

Tuist 不会自动启用任一功能。要 opting in，请将以下内容添加到 `gradle.properties` 中：

```properties
org.gradle.configuration-cache=true
org.gradle.unsafe.isolated-projects=true
```

你的构建脚本和其他插件也必须支持这些功能。Gradle 在存储配置缓存时会报告兼容性问题。

## 配置参考 {#configuration-reference}

以下选项可在 `settings.gradle.kts` 中的 `tuist` 扩展块中使用：

| 选项 | 类型 | 默认值 | 描述 |
| --- | --- | --- | --- |
| `project` | `String?` | `null`（可选） | 采用 `account/project` 格式的项目标识符。如果未设置，插件将从 `tuist.toml` 中读取。 |
| `url` | `String?` | `null` | Tuist 服务器的基础 URL。如果未设置，则默认为 `"https://tuist.dev"` 或 `tuist.toml` 中定义的值。 |
| `uploadInBackground` | `Boolean?` | `null` | 是否在后台上传构建和测试洞察。当为 `null`（默认值）时，上传在本地构建时在后台运行，在持续集成运行器上在前台运行。 |
| `stressNewTests.mode` | `String?` | `null` | `"report"` 或 `"enforce"`。重新运行构建添加的测试用例，并标记任何证明为不稳定的用例；请参阅 <.localized_link href="/guides/features/test-insights/flaky-tests/gradle#stress-testing-new-tests">对新测试进行压力测试</.localized_link>。未设置时关闭。 |

对于使用 `http://` URL 的本地服务器，仅在该本地配置中允许不安全协议：

```kotlin
tuist {
    buildCache {
        allowInsecureProtocol = true
    }
}
```

不要为托管或其他 `https://` 服务器启用 `allowInsecureProtocol`。

> [!NOTE]
> **Tuist.toml**
>
> 配置 `project`（以及可选的 `url`）的推荐方式是通过项目根目录中的 `tuist.toml` 文件。这样，配置就可以在 Tuist 命令行界面和 Gradle 插件之间共享。如果需要，你仍然可以在 `settings.gradle.kts` 中覆盖这些值。

```toml
project = "account/project"
url = "https://tuist.dev"
```

## HTTP 代理 {#http-proxy}

如果你的网络通过 HTTP 代理路由出站流量，请参阅 <.localized_link href="/guides/integrations/http-proxy">HTTP 代理指南</.localized_link>。

## 后续步骤 {#next-steps}

安装并配置插件后，你可以启用：

- <.localized_link href="/guides/features/cache/gradle-cache">远程构建缓存</.localized_link>，以便在你的团队和持续集成运行器之间共享构建产物。
- <.localized_link href="/guides/features/build-insights/gradle">构建洞察</.localized_link>，用于在 Tuist 仪表板中跟踪任务耗时和缓存行为。
- <.localized_link href="/guides/features/test-insights/gradle">测试洞察</.localized_link>，用于跟踪测试性能并检测不稳定测试。
- <.localized_link href="/guides/features/test-insights/flaky-tests">不稳定测试</.localized_link>，用于自动检测、跟踪和隔离不稳定测试。
