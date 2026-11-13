---
{
  "title": "Xcode 不稳定测试",
  "titleTemplate": ":title · 不稳定测试 · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 检测、管理并隔离 Xcode 项目中的不稳定测试。"
}
---
# Xcode 不稳定测试 {#xcode-flaky-tests}

> [!IMPORTANT]
> **要求**
>
> - 已配置 <.localized_link href="/guides/features/test-insights/xcode">Xcode 测试洞察</.localized_link>。Tuist 会根据每次测试运行上传的测试洞察事件来检测不稳定测试。

<!-- @snippet: ./_intro -->

![不稳定测试页面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不稳定检测的工作原理 {#how-it-works}

Tuist 通过两种方式检测不稳定测试：

### 测试重试 {#test-retries}

当你使用重试功能运行测试时，Tuist 会分析每次尝试的结果。如果某个测试在某些尝试中失败而在其他尝试中通过，它会被标记为不稳定。

通过 `tuist xcodebuild test` 传递 `-retry-tests-on-failure` 或 `-test-iterations`：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![不稳定测试用例详情](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## 隔离不稳定测试 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

被隔离的测试处于以下两种模式之一：

- **静音**：测试仍会运行，但 `tuist xcodebuild test` 会屏蔽失败结果。失败结果仍会提供给不稳定测试检测器，因此你可以继续观察该测试而不会导致构建失败。对于正在积极调查的测试，请选择此模式。
- **跳过**：xcodebuild 会收到 `-skip-testing <identifier>`，因此测试永远不会启动。它不会产生新结果，并从不稳定测试仪表板中消失，直到你重新启用它。当测试损坏、缓慢或持续不稳定以至于运行它只会浪费 CI 分钟数时，请选择此模式。

<!-- @snippet: ./_quarantined-passing -->

### 运行测试 {#running-tests}

`tuist xcodebuild test` 是一个透传包装器，会自动支持这两种模式。像调用 xcodebuild 一样使用它：

```sh
tuist xcodebuild test -scheme MyScheme
```

跳过的测试会以 `-skip-testing <identifier>` 的形式附加到你的 xcodebuild 调用中，并且永远不会启动。静音测试正常运行；如果它们失败，失败结果会在最终的构建状态中被屏蔽。

#### 绕过隔离 {#bypassing-quarantine}

`tuist xcodebuild test` 接受 `--skip-quarantine` 以运行所有内容，包括静音和跳过的测试：

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### 直接调用 xcodebuild {#calling-xcodebuild-directly}

如果你无法通过 `tuist xcodebuild test` 运行，可以使用 `tuist test case list` 自行将被隔离的测试展开为 `-skip-testing` 参数：

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

这是在 `tuist xcodebuild test` 之外的安全默认行为：静音测试的失败屏蔽仅在你通过该命令运行时生效，因此跳过这两种模式可以避免虚假的 CI 失败。如果你需要更精细的控制，请改用 `tuist xcodebuild test`。

## 对新测试进行压力测试 {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

如果一个测试用例在过去 90 天内未在项目的默认分支上或在已合并到该分支的提交中于 CI 上运行过，则被视为新测试用例。使用合并队列时，队列运行的测试用例在队列的提交合并后即被知晓，如果队列将其丢弃，则该测试用例保持为新测试用例。提交是通过 Tuist 在 CI 上收集的 <.localized_link href="/guides/features/test-insights/xcode#git-history">Git 历史</.localized_link> 进行匹配的。

<!-- @snippet: ./_stress-modes -->

将其放在透传参数之前，或者设置 `TUIST_TEST_STRESS_NEW_TESTS` 以针对每个 CI 通道调整模式：

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

<!-- @snippet: ./_stress-reruns -->

重新运行会复用第一次运行构建的内容。

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
