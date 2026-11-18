---
{
  "title": "生成的 Xcode 项目",
  "titleTemplate": ":title · 不稳定测试 · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 生成的 Xcode 项目中检测、管理和隔离不稳定测试。"
}
---
# 生成的 Xcode 项目 {#generated-xcode-project-flaky-tests}

> [!IMPORTANT]
> **要求**
>
> - 已配置 <.localized_link href="/guides/features/test-insights/xcode">Xcode 测试洞察</.localized_link>（自动生成的 Scheme 包含 `tuist inspect test` 后置操作；自定义 Scheme 需要手动添加）。

<!-- @snippet: ./_intro -->

![不稳定测试页面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不稳定检测的工作原理 {#how-it-works}

Tuist 通过两种方式检测不稳定测试：

### 测试重试 {#test-retries}

当你运行带有重试功能的测试时，Tuist 会分析每次尝试的结果。如果某个测试在某些尝试中失败而在其他尝试中通过，它将被标记为不稳定。

通过 `tuist test` 传递 `-retry-tests-on-failure` 或 `-test-iterations`：

```sh
tuist test MyScheme -- -retry-tests-on-failure -test-iterations 3
```

![不稳定测试用例详情](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## 隔离不稳定测试 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

被隔离的测试处于以下两种模式之一：

- **静默**：测试仍然运行，但 `tuist test` 会屏蔽失败结果。失败结果仍会提供给不稳定测试检测器，因此你可以在不中断构建的情况下继续观察该测试。对于正在积极调查的测试，请选择此模式。
- **跳过**：xcodebuild 会收到 `-skip-testing <identifier>`，因此测试永远不会启动。它不会产生新的结果，并从 unstable-tests 仪表板中移除，直到你重新启用它。当测试损坏、运行缓慢或不稳定程度极高以至于运行它只会浪费 CI 分钟数时，请选择此模式。

<!-- @snippet: ./_quarantined-passing -->

### 运行测试 {#running-tests}

`tuist test` 会自动遵循这两种模式：

```sh
tuist test
```

跳过的测试会以 `-skip-testing` 的形式传递给 xcodebuild，且永远不会启动。静默的测试正常运行；如果它们失败，失败结果将在最终的构建状态中被屏蔽。

要完全绕过隔离并运行所有内容（包括静默和跳过的测试）：

```sh
tuist test --skip-quarantine
```

## 对新测试进行压力测试 {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

如果一个测试用例在过去 90 天内未在项目的默认分支上或在已合并到该分支的提交中于 CI 上运行过，则被视为新测试用例。使用合并队列时，队列运行的测试用例在队列的提交合并后即被知晓，如果队列将其丢弃，则该测试用例保持为新测试用例。提交是通过 Tuist 在 CI 上收集的 <.localized_link href="/guides/features/test-insights/xcode#git-history">Git 历史记录</.localized_link> 进行匹配的。

<!-- @snippet: ./_stress-modes -->

在这两种模式下，<.localized_link href="/guides/features/selective-testing/generated-xcode-project">选择性测试</.localized_link> 都不会在下一次运行中跳过包含不稳定新测试用例的测试目标。该目标将再次运行，网关将再次对该测试用例进行压力测试，直到其通过所有重运行为止。

将其放在透传参数之前，或设置 `TUIST_TEST_STRESS_NEW_TESTS` 以针对每个 CI 通道更改模式：

```sh
tuist test --stress-new-tests report
```

<!-- @snippet: ./_stress-reruns -->

重运会复用第一次构建所生成的内容。

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
