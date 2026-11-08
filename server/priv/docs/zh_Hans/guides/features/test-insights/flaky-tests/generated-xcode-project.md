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

当你运行带有重试功能的测试时，Tuist 会分析每次尝试的结果。如果某次测试在某些尝试中失败而在其他尝试中通过，则会被标记为不稳定。

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

- **跳过**：xcodebuild 会收到 `tuist test`，因此测试永远不会启动。它不会产生新的结果，并从不稳定测试仪表板中消失，直到你重新启用它。当测试损坏、缓慢或不稳定程度极高，以至于运行它只会浪费 CI 分钟数时，请选择此模式。
- **跳过**：xcodebuild 会收到 `-skip-testing <identifier>`，因此该测试永远不会启动。它不会产生新的结果，并从 unstable-tests 仪表板中移除，直到你重新启用它。当测试损坏、缓慢或持续不稳定以至于运行它只是浪费 CI 分钟数时，请选择此选项。

<!-- @snippet: ./_quarantined-passing -->

### {#running-tests} 会自动遵循这两种模式：

跳过的测试会以 `tuist test` 的形式传递给 xcodebuild，且永远不会启动。静音测试正常运行；如果它们失败，失败结果会在最终的构建状态中被屏蔽。

```sh
tuist test
```

跳过的测试会以 `-skip-testing` 的形式传递给 xcodebuild，并且永远不会启动。静音测试正常运行；如果它们失败，失败信息会在最终的构建状态中被屏蔽。

要完全绕过隔离并运行所有内容，包括静音和跳过的测试：

```sh
tuist test --skip-quarantine
```

## 对新测试进行压力测试 {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

在这两种模式下，<.localized_link href="/guides/features/test-insights/xcode#git-history">选择性测试</.localized_link>都不会在下一次运行时跳过包含不稳定新测试用例的测试目标。该目标会再次运行，门禁会再次对该测试用例进行压力测试，直到其通过所有重试。

<!-- @snippet: ./_stress-modes -->

在这两种模式下，<.localized_link href="/guides/features/selective-testing/generated-xcode-project">选择性测试</.localized_link> 不会在下一次运行时跳过包含不稳定新测试用例的测试目标。该目标会再次运行，门禁会再次对该测试用例进行压力测试，直到它通过所有重运行为止。

将其放在透传参数之前，或设置 `TUIST_TEST_STRESS_NEW_TESTS` 以针对每个 CI 通道调整模式：

```sh
tuist test --stress-new-tests report
```

<!-- @snippet: ./_stress-reruns -->

重运行会复用第一次构建的内容。

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
