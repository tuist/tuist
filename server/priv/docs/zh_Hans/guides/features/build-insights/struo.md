---
{
  "title": "Struo 构建洞察",
  "titleTemplate": ":title · 构建洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 仪表板中实时跟踪 Struo 运行，并检查操作、耗时、失败和缓存决策。"
}
---
# Struo 构建洞察 {#struo-build-insights}

<a id="once-build-insights"></a>

Struo 会在执行过程中将运行流式传输到 Tuist，因此你可以实时跟踪进度，无需等待最终的 CI 日志。打开在运行开始时打印的仪表板链接，以检查其图表、操作状态和缓存决策。

> [!IMPORTANT]
> **要求**
>
> - 完成 <.localized_link href="/guides/get-started/struo-project">Struo 入门指南</.localized_link> 并对运行 Struo 的机器进行身份验证。

## 报告你的构建 {#report-your-builds}

继续使用你的 Struo 命令：

```bash
struo build MyApplication
```

实时报告采用尽力而为的方式。报告端点不可用或会话过期不会导致构建失败。如果会话过期，请使用 `struo auth login --provider tuist` 重新登录。

## 仪表板显示内容 {#what-the-dashboard-shows}

使用 **构建** 和 **构建运行** 来比较不同时间、分支以及本地或 CI 环境中的运行。每次运行可以包括：

- 请求的命令、状态、开始时间和持续时间。
- Struo 版本和报告的主机信息。
- 操作及其依赖项、状态、持续时间和缓存结果。
- 报告的操作错误。
- 客户端报告的 Git 分支、提交和 CI 上下文。

搜索和过滤操作以查找失败或缓慢的工作。报告的操作名称和源文件有助于将工作回溯到代码；较旧的客户端可能提供较少的详细信息。缓存或跳过的操作不是已执行的工作，缺少计时信息也不代表执行时长为零。

Tuist 目前不摄取 Struo 的原始操作日志流。请保留 CI 日志以获取完整的进程输出；运行摘要和结构化错误不能替代这些日志。

**缓存** 视图将操作决策与内容对象传输分开。请参阅 <.localized_link href="/guides/features/cache/struo">Struo 缓存</.localized_link> 以了解如何解读缓存活动。

## 测试 {#tests}

测试命令也会产生 Struo 运行。它们报告的套件和用例出现在 **测试** 下；托管的分片还会发布合并的测试运行。请参阅 <.localized_link href="/guides/features/test-insights/struo">Struo 测试洞察</.localized_link>。

## 编码代理和 Grafana {#coding-agents-and-grafana}

<.localized_link href="/guides/features/agentic-coding/mcp#struo-runs">模型上下文协议工具</.localized_link> 允许代理列出 Struo 运行并读取运行的操作和缓存总数。同样的读取功能也可通过 HTTP API 获得。

使用 <.localized_link href="/guides/integrations/grafana">Grafana 集成</.localized_link> 获取最终的 Struo 构建健康指标。Struo 目前不报告经过的缓存时间节省，因此该测量值保持为不可用，而不是零。
