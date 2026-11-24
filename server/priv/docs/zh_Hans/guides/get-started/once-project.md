---
{
  "title": "Once 项目",
  "titleTemplate": ":title · 入门指南 · 指南 · Tuist",
  "description": "将 Once 连接到 Tuist，以使用共享缓存、实时构建与测试洞察、测试分片以及应用预览功能。"
}
---
# Once 项目 {#once-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/once-project
```

:::

[Once](https://buildonce.dev) 运行可缓存的脚本和构建图。将其连接到 Tuist，即可在多台机器间共享缓存成果、实时跟踪运行状态，并发布应用供团队试用。保留你现有的项目源码和构建定义；集成配置位于 `once.toml`。

## 前置条件

- 已安装 [Once](https://buildonce.dev/docs/guide/getting-started)，并拥有一个工作区或可缓存的脚本。
- 一个 Tuist 账号。Once 集成不需要 Tuist CLI。

## 连接项目 {#connect-the-project}

在仓库根目录下运行：

```bash
once connect --provider tuist --create
```

Once 会在需要时为你登录，在你的个人账号下创建一个 Tuist 项目，并将提供商绑定写入 `once.toml`。请参阅 [连接项目](https://buildonce.dev/docs/guide/infrastructure/connect) 以选择其他账号或现有项目。

对于现有的 Tuist 项目，请自行配置提供商和缓存绑定：

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
# url = "https://your-tuist-server.example.com"

[infrastructure.cache]
provider = "tuist"
```

将 `acme` 和 `app` 替换为你的账号和项目标识符，然后进行身份验证：

```bash
once auth login --provider tuist
```

提交 `once.toml`，以便你的团队成员和 CI 共享目标配置，而不是你的凭据。每位开发者需在自己的机器上登录。

## 共享缓存

本地缓存仅对填充该缓存的机器有帮助。配置 Tuist 后，Once 可以恢复由其他开发者或 CI 产生的匹配结果，而无需重新执行相同的工作。

照常运行你的可缓存脚本或图目标：

```bash
once build MyApplication
```

在仪表板中打开 **Once Cache** 以检查远程缓存活动。请参阅 <.localized_link href="/guides/features/cache/once">Once 缓存</.localized_link> 了解设置方法和跨机器复用检查。

## 构建洞察

运行开始时，Once 会打印一个仪表板链接。打开该链接可在运行过程中跟踪图结构、操作状态和缓存决策。使用 **Builds** 比较本地与 CI 性能并调查失败的操作。保留 CI 日志以获取完整的进程输出；目前不支持原始操作日志摄入。

请参阅 <.localized_link href="/guides/features/build-insights/once">Once 构建洞察</.localized_link> 了解记录的内容以及如何从编码代理或 Grafana 访问这些数据。

## 测试洞察与分片

运行你的 Once 测试目标：

```bash
once test
```

打开 **Tests** 以检查报告的套件、用例、持续时间和失败情况。结果取决于测试目标的报告能力；运行测试进程的操作不会自动生成每个用例的测试报告。

当套件规模超出单机处理能力时，创建托管分片计划并将其批次分发到 CI 工作节点。请参阅 <.localized_link href="/guides/features/test-insights/once">Once 测试洞察</.localized_link> 和 <.localized_link href="/guides/features/test-sharding/once">Once 测试分片</.localized_link>。

## 预览与包体积

向同一提供商添加构件绑定，以发布受支持的 Android、Apple 模拟器和 macOS 应用：

```toml
[infrastructure.artifacts]
name = "tuist"
```

```bash
once artifact publish MyApplication --track review
```

返回的链接将打开你项目的预览；处理可能需要片刻时间。请参阅 <.localized_link href="/guides/features/previews/once">Once 预览</.localized_link> 了解签名要求以及构建后的可选发布流程。

要跟踪包体积，请针对已构建的 `.app`、`.ipa`、`.xcarchive`、`.apk` 或 `.aab` 单独使用 Tuist CLI。遵循 <.localized_link href="/guides/features/bundle-insights">Apple 或 Android 包体积洞察指南</.localized_link>；发布 Once 构件不会自动上传包体积报告。

## 持续集成

在 `TUIST_TOKEN` 中使用获授权执行项目操作的账号令牌，或通过受支持的 CI 提供商的 OpenID Connect 身份进行身份验证：

```bash
once auth login --provider tuist --no-browser
once build MyApplication
once test
```

在 GitHub Actions 上，为作业授予 `id-token: write` 和 `contents: read` 权限。参考 <.localized_link href="/guides/integrations/continuous-integration#once">Once 在持续集成中的使用</.localized_link> 获取示例。个人开发者登录凭据不适用于 CI。

## 远程执行

启用了远程执行的账号还可以在 Tuist 的 Linux 工作节点上运行符合条件的图命令操作。这与共享缓存结果以及运行整个 CI 工作流是分开的。请参阅 <.localized_link href="/guides/features/runners/once">Once 远程执行</.localized_link> 了解工作节点要求和设置方法。
