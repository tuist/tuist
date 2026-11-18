---
{
  "title": "一次性构建洞察",
  "titleTemplate": ":title · 构建洞察 · 功能 · 指南 · Tuist",
  "description": "跟踪一次性运行的实时状态，并在 Tuist 仪表盘中检查操作、耗时、失败以及缓存决策。"
}
---
# Once 构建洞察 {#once-build-insights}

Once 会在执行期间将运行流式传输到 Tuist，因此你无需等待最终的 CI 日志即可跟踪进度。打开在运行开始时打印的仪表板链接，以检查其依赖图、操作状态和缓存决策。

> [!IMPORTANT]
> **要求**
>
> - 完成<.localized_link href="/guides/get-started/once-project">Once 入门指南</.localized_link>并对运行 Once 的机器进行身份验证。

## 报告你的构建 {#report-your-builds}

继续使用你的 Once 命令：

```bash
once build MyApplication
```

实时报告采用尽力而为机制。报告端点不可用或会话过期不会导致构建失败。如果会话过期，请使用 `once auth login --provider tuist` 重新登录。

## 仪表板显示内容 {#what-the-dashboard-shows}

使用**构建**和**构建运行**来比较不同时间、分支以及本地或 CI 环境中的运行。每次运行可以包括：

- 请求的命令、状态、开始时间和持续时间。
- Once 版本和报告的主机信息。
- 操作及其依赖项、状态、持续时间和缓存结果。
- 报告的操作错误。
- 由客户端报告的 Git 分支、提交和 CI 上下文。

搜索和过滤操作以查找失败或缓慢的任务。报告的操作名称和源文件有助于将工作回溯到代码；较旧的客户端可能提供较少的详细信息。缓存或跳过的操作不属于已执行的工作，缺少计时信息也不代表执行时长为零。

Tuist 目前不摄取 Once 的原始操作日志流。请保留 CI 日志以获取完整的进程输出；运行摘要和结构化错误不能替代这些日志。

**缓存**视图将操作决策与内容对象传输分开。请参阅<.localized_link href="/guides/features/cache/once">Once 缓存</.localized_link>以了解如何解读缓存活动。

## 测试 {#tests}

测试命令也会生成 Once 运行。它们报告的套件和用例会显示在**测试**下；托管的分片还会发布一个合并的测试运行。请参阅<.localized_link href="/guides/features/test-insights/once">Once 测试洞察</.localized_link>。

## 编码代理和 Grafana {#coding-agents-and-grafana}

<.localized_link href="/guides/features/agentic-coding/mcp#once-runs">模型上下文协议工具</.localized_link>允许代理列出 Once 运行并读取运行的操作和缓存总数。通过 HTTP API 也可以获得相同的读取能力。

使用<.localized_link href="/guides/integrations/grafana">Grafana 集成</.localized_link>获取最终的 Once 构建健康指标。Once 目前不报告缓存节省的时间，因此该测量值保持为不可用，而非零。
