---
{
  "title": "Struo 项目",
  "titleTemplate": ":title · 入门指南 · 指南 · Tuist",
  "description": "将 Struo 与 Tuist 连接，以实现共享缓存、实时构建和测试洞察、测试分片以及应用预览。"
}
---
# Struo 项目 {#struo-project}

<a id="once-project"></a>

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/struo-project
```

:::

[Struo](https://struo.run) 运行可缓存的脚本和构建图。将其连接到 Tuist，以便在多台机器之间共享缓存成果、实时跟踪运行状态，并发布应用供团队试用。保留现有的项目源码和构建定义；集成配置位于 `struo.toml`。

## 前置条件

- 已安装 [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) 或更高版本，并拥有一个工作区或可缓存脚本。请按照 [安装指南](https://struo.run/docs/guide/getting-started) 操作，或使用 mise 固定版本：

  ```bash
  mise use -g github:tuist/struo@1.0.0
  ```

- 一个 Tuist 账户。Struo 集成不需要 Tuist CLI。

## 从 Once 升级 {#upgrading-from-once}

Struo 是 Once 的新名称。将 `once.toml` 文件重命名为 `struo.toml`，将 mise 固定源从 `github:tuist/once` 更新为 `github:tuist/struo`，并将 `once` 命令替换为 `struo`。将脚本头部从 `# once` 更新为 `# struo`，并将 shebang 更新为 `#!/usr/bin/env -S struo exec -- bash`。将 `ONCE_*` 环境变量重命名为 `STRUO_*`，例如 `STRUO_CACHE_PROVIDER`；Tuist 凭据仍使用 `TUIST_TOKEN`。

将忽略文件中的 `.once/` 条目更改为 `.struo/`。输出现在位于 `.struo/out/` 下，共享的本地内容缓存使用 `$XDG_CACHE_HOME/struo/cas`（默认为 `~/.cache/struo/cas`）。缓存键和本地存储使用新名称，因此升级后本地缓存将为空，而不是迁移旧的缓存条目。请使用 `struo auth login --provider tuist` 重新登录。

重命名不会改变 Tuist 的兼容性端点：实时报告仍使用 `once.events.v1`，现有的 `/api/.../once` 路由仍然受支持。请参阅 [上游重命名指南](https://struo.run/changelog/2026-11-18-once-is-now-struo)。

## 连接项目 {#connect-the-project}

从仓库根目录运行：

```bash
struo connect --provider tuist --create
```

Struo 会在需要时为你登录，在你的个人账户下创建一个 Tuist 项目，并将提供者绑定写入 `struo.toml`。请参阅 [连接项目](https://struo.run/docs/guide/infrastructure/connect) 以选择其他账户或现有项目。

对于现有的 Tuist 项目，请自行配置提供者和缓存绑定：

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
# url = "https://your-tuist-server.example.com"

[infrastructure.cache]
provider = "tuist"
```

将 `acme` 和 `app` 替换为你的账户和项目标识符，然后进行身份验证：

```bash
struo auth login --provider tuist
```

提交 `struo.toml`，以便你的团队成员和 CI 共享目标配置，而不是你的凭据。每位开发者需在自己的机器上登录。

## 共享缓存

本地缓存仅对填充该缓存的机器有帮助。配置 Tuist 后，Struo 可以恢复由其他开发者或 CI 生成的匹配结果，而无需再次运行相同的工作。

像往常一样运行你的可缓存脚本或图目标：

```bash
struo build MyApplication
```

在仪表板中打开 **Struo Cache** 以检查远程缓存活动。请参阅 <.localized_link href="/guides/features/cache/struo">Struo 缓存</.localized_link> 了解设置方法和跨机器复用检查。

## 构建洞察

Struo 在运行开始时会打印一个仪表板链接。打开该链接，以便在运行过程中跟踪图结构、操作状态和缓存决策。使用 **Builds** 比较本地和 CI 性能，并调查失败的操作。保留 CI 日志以获取完整的进程输出；目前不支持原始操作日志摄入。

请参阅 <.localized_link href="/guides/features/build-insights/struo">Struo 构建洞察</.localized_link> 了解记录的内容以及如何从编码代理或 Grafana 访问这些数据。

## 测试洞察与分片

运行你的 Struo 测试目标：

```bash
struo test
```

打开 **Tests** 以检查报告的套件、用例、持续时间和失败情况。结果取决于测试目标的报告能力；运行测试进程的操作不会自动生成每个用例的测试报告。

当套件规模超出单机处理能力时，创建托管分片计划并将其批次分发到 CI 工作节点。请参阅 <.localized_link href="/guides/features/test-insights/struo">Struo 测试洞察</.localized_link> 和 <.localized_link href="/guides/features/test-sharding/struo">Struo 测试分片</.localized_link>。

## 预览与包大小

向同一提供者添加构件绑定，以发布支持的 Android、Apple 模拟器和 macOS 应用：

```toml
[infrastructure.artifacts]
name = "tuist"
```

```bash
struo artifact publish MyApplication --track review
```

返回的链接会打开你项目的预览；处理可能需要一点时间。请参阅 <.localized_link href="/guides/features/previews/struo">Struo 预览</.localized_link> 了解签名要求以及构建后的可选发布流程。

要跟踪包大小，请针对已构建的 `.app`、`.ipa`、`.xcarchive`、`.apk` 或 `.aab` 单独使用 Tuist CLI。请遵循 <.localized_link href="/guides/features/bundle-insights">Apple 或 Android 包大小洞察指南</.localized_link>；发布 Struo 构件不会自动上传包大小报告。

## 持续集成

在 `TUIST_TOKEN` 中使用对项目操作授权的账户令牌，或通过支持的 CI 提供者的 OpenID Connect 身份进行身份验证：

```bash
struo auth login --provider tuist --no-browser
struo build MyApplication
struo test
```

在 GitHub Actions 上，为作业授予 `id-token: write` 和 `contents: read` 权限。请参阅 <.localized_link href="/guides/integrations/continuous-integration#struo">持续集成中的 Struo</.localized_link> 获取示例。个人开发者登录不是 CI 凭据。

## 远程执行

启用了远程执行的账户还可以在 Tuist 的 Linux 工作节点上运行符合条件的图命令操作。这与共享缓存结果以及运行整个 CI 工作流是分开的。请参阅 <.localized_link href="/guides/features/runners/struo">Struo 远程执行</.localized_link> 了解工作节点要求和设置方法。
