---
{
  "title": "Gradle 不稳定测试",
  "titleTemplate": ":title · 不稳定测试 · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 检测、管理并隔离 Gradle 项目中的不稳定测试。"
}
---
# Gradle 不稳定测试 {#gradle-flaky-tests}

> [!IMPORTANT]
> **要求**
>
> - 已配置<.localized_link href="/guides/features/test-insights/gradle">Gradle 测试洞察</.localized_link>。

<!-- @snippet: ./_intro -->

![不稳定测试页面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不稳定检测的工作原理 {#how-it-works}

Tuist 通过两种方式检测不稳定测试：

### 测试重试 {#test-retries}

当你使用重试功能运行测试时，Tuist 会分析每次尝试的结果。如果某个测试在某些尝试中失败而在其他尝试中通过，它会被标记为不稳定。

你可以使用[Test Retry 插件](https://github.com/gradle/test-retry-gradle-plugin)或类似机制来重新运行失败的测试。Tuist 将检测到那些在某些尝试中通过而在其他尝试中失败的测试。

将该插件添加到你的 `build.gradle.kts`：

```kotlin
plugins {
    id("org.gradle.test-retry") version "1.6.2"
}

tasks.test {
    retry {
        maxRetries = 3
        maxFailures = 5
        failOnPassedAfterRetry = false
    }
}
```

![不稳定测试用例详情](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 跨运行检测 {#cross-run-detection}

即使没有测试重试，Tuist 也可以通过比较同一提交和同一 Gradle 项目在不同 CI 运行中的结果来检测不稳定测试。如果某个测试在一次 CI 运行中通过，但在同一提交和项目的另一次运行中失败，则该失败的执行会被标记为不稳定。

Gradle 项目是比较键的一部分，因为同一个测试在不同项目中可能表现出确定性的差异——例如，一个共享的测试类使用不同的依赖项编译，或在不同的模块夹具上运行。同一提交在不同 Gradle 项目上的两次运行被视为独立的执行变体，不会互相标记为不稳定。

这对于捕获那些失败频率不足以被重试捕获、但仍会导致间歇性 CI 失败的不稳定测试特别有用。

<!-- @snippet: ./_managing -->

## 隔离不稳定测试 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

被隔离的测试处于以下两种模式之一：

- **静音**：测试仍然运行，但插件会设置 `ignoreFailures = true`，并且仅在非隔离失败时使构建再次失败。失败信息仍会提供给不稳定测试检测器，因此你可以在不破坏构建的情况下继续观察该测试。对于你正在积极调查的测试，请选择此模式。
- **跳过**：插件通过 Gradle 的 `excludeTestsMatching` 过滤掉该测试，因此它永远不会启动。它不会产生新结果，并从 unstable-tests 仪表板中消失，直到你重新启用它。当测试损坏、缓慢或不稳定程度极高以至于运行它只会浪费 CI 分钟数时，请选择此模式。

<!-- @snippet: ./_quarantined-passing -->

### 启用隔离 {#enabling-quarantine}

隔离在 CI 上**自动启用**（当设置了 `CI` 环境变量时），并在本地构建中禁用。插件在每个测试任务之前从 Tuist 服务器获取隔离测试列表；静音测试正常运行并屏蔽其失败，跳过的测试则被过滤掉。

你可以在 `settings.gradle.kts` 中显式控制此行为：

```kotlin
tuist {
    testQuarantine {
        enabled = true  // or false to disable
    }
}
```

当未设置 `enabled` 时，默认为自动检测：在 CI 上启用，在本地禁用。

## 对新测试进行压力测试 {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

如果一个测试用例在过去 90 天内未在项目的默认分支上运行过 CI，或未在已合并到该分支的提交上运行过 CI，则被视为新测试用例。在使用合并队列时，一旦队列的提交落地，队列运行过的测试用例即被知晓；如果队列将其丢弃，则该测试用例保持为新测试用例。提交通过 Tuist 在 CI 上收集的<.localized_link href="/guides/features/test-insights/gradle#git-history">Git 历史</.localized_link>进行匹配。

<!-- @snippet: ./_stress-modes -->

在 `settings.gradle.kts` 中声明，或设置 `TUIST_TEST_STRESS_NEW_TESTS` 以针对每个 CI 通道调整模式：

```kotlin
tuist {
    stressNewTests {
        mode = "report" // or "enforce"
    }
}
```

与隔离不同，该门禁没有感知 CI 的默认值。如果未设置 `mode`，它不会在任何地方运行。

<!-- @snippet: ./_stress-reruns -->

每次重跑都是一个嵌套的 Gradle 构建，仅过滤到该单个测试用例，因此每次重跑都会获得一个全新的测试 JVM。

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
