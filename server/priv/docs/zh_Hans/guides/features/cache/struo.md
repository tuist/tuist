---
{
  "title": "Struo 缓存",
  "titleTemplate": ":title · 缓存 · 功能 · 指南 · Tuist",
  "description": "通过 Tuist 的远程缓存，在开发者机器和 CI 之间共享 Struo 操作结果。"
}
---
# Struo 缓存 {#struo-cache}

<a id="once-cache"></a>

Struo 可以在本地复用结果，但开发者的本地缓存无法共享给团队成员或全新的 CI 工作节点。Tuist 提供共享的远程缓存，因此匹配的工作只需在一台机器上运行。

## 设置 {#setup}

完成<.localized_link href="/guides/get-started/struo-project#connect-the-project">Struo 入门指南</.localized_link>，然后检查代码仓库中 `struo.toml` 的缓存绑定配置：

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.cache]
provider = "tuist"
```

使用 `struo auth login --provider tuist` 进行身份验证。无需安装 Tuist 可执行文件或额外的缓存插件。同一提供商支持[可缓存脚本](https://struo.run/docs/guide/scripted/caching)和[图目标](https://struo.run/docs/guide/graph)。

只有被 Struo 声明为可缓存的工作才能被复用。请声明工作所依赖的输入、输出和环境变量；配置远程缓存并不会使任意命令变得可重现。

## 验证共享复用 {#verify-shared-reuse}

在两台具有匹配输入和配置的机器上运行相同的可缓存脚本或图目标：

```bash
struo build MyApplication
```

第一台机器会填充共享缓存。在另一台本地缓存中尚未存在该结果的机器上，缓存命中并恢复的输出内容证实了远程复用。仅在第一台机器上重复执行命令只能证明本地命中，并不能说明结果由 Tuist 提供。

## 检查缓存活动 {#inspect-cache-activity}

在 Tuist 项目中打开**Struo Cache**，以检查操作缓存命中、传输、延迟和吞吐量。打开某次运行的**Cache**视图，以检查其报告的操作决策和内容对象活动。

操作结果和内容对象回答的是不同的问题：缺少操作结果意味着 Struo 必须执行该工作，而内容对象请求则用于传输输入或输出。不要将 blob 下载视为已执行的操作或操作缓存命中。

有关运行的操作图和结构化错误，请参阅<.localized_link href="/guides/features/build-insights/struo">Struo 构建洞察</.localized_link>。

## 持续集成 {#continuous-integration}

使用 `TUIST_TOKEN` 或 Struo 的无头 OIDC 登录，如<.localized_link href="/guides/integrations/continuous-integration#struo">持续集成中的 Struo</.localized_link>所述。请勿将凭据存入 `struo.toml`。

账户的<.localized_link href="/guides/features/cache#restrict-uploads-to-ci">缓存上传策略</.localized_link>决定了谁可以发布结果。只读开发者可以使用 CI 生成的条目，而无需成为缓存写入者。

有关连接重试和故障排除，请参阅[Struo 的 Tuist 集成](https://struo.run/docs/guide/infrastructure/tuist#connection-recovery)。重试不会使中断的上传变为可恢复。
