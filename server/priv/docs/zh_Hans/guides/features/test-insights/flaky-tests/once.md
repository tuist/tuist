---
{
  "title": "一次性不稳定测试",
  "titleTemplate": ":title · 不稳定测试 · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "通过报告的重试尝试和 CI 历史记录，检测并调查一次性不稳定测试。"
}
---
# Once 不稳定测试 {#once-flaky-tests}

> [!IMPORTANT]
> **要求**
>
> - 使用结构化的单个测试结果配置 <.localized_link href="/guides/features/test-insights/once">Once 测试洞察</.localized_link>。

<!-- @snippet: ./_intro -->

## 不稳定测试检测的工作原理 {#how-it-works}

### 测试重试 {#test-retries}

当运行器报告同一测试的多次尝试时，Tuist 会保留这些记录。先失败后通过的测试会被标记为不稳定；持续失败的测试仍视为失败。在底层运行器支持的情况下启用重试。将 Once 连接到 Tuist 并不会自动为每个测试目标添加重试。

### 跨运行检测 {#cross-run-detection}

共享的测试历史还允许 Tuist 比较 CI 中同一测试和提交的通过与失败结果。Once 必须报告提交和 CI 上下文以进行此比较；本地运行仍然可见，但不会自动成为跨运行的不稳定证据。

测试用例通过原生目标、套件和用例名称进行标识。保持这些标识稳定以保留其历史记录，并使用完整的每个用例的报告，而不是从目标的整体结果推断可靠性。

## 调查不稳定测试 {#investigate-flaky-tests}

在 Tuist 中打开测试用例的历史记录，以比较其尝试、失败和受影响的 CI 提交。还可以通过 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 工具</.localized_link> 使用共享测试查询，以便编码代理调查相同的报告结果。

## 管理不稳定测试 {#managing-flaky-tests}

在调查失败时，你可以从详细信息页面将测试标记或取消标记为不稳定。默认的不稳定测试检测自动化也会在恢复窗口期后清除该标志，通常为 14 天内没有再次触发。

Once 项目目前未公开 **自动化** 设置选项卡。检测和存储的测试状态可用，但针对具有隔离强制执行功能的构建系统所记录的设置工作流程尚未在 Once 中公开。

## 隔离 {#quarantining}

Tuist 可以将报告的用例归因于其存储的隔离状态，但原生 Once 客户端目前不会获取并强制执行 Tuist 的 **静音** 或 **跳过** 策略。在 Tuist 中更改该状态不会阻止 Once 执行测试，也不会使其失败停止阻塞 CI。

当需要执行时隔离时，请使用运行器自身的过滤或失败策略。不要仅依赖仪表板状态来更改命令的退出代码。

## Slack 通知 {#slack-notifications}

Once 项目目前未公开用于配置不稳定测试 Slack 警报的项目设置工作流程。使用下面的共享测试查询，将报告的不稳定状态与你自己的通知集成。

<!-- @snippet: ./_querying -->
