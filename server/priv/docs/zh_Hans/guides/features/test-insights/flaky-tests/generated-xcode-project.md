---
{
  "title": "生成的 Xcode 项目",
  "titleTemplate": ":title · 不稳定测试 · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 生成的 Xcode 项目中检测、管理和隔离不稳定测试。"
}
---
# 生成的 Xcode 项目 {#generated-xcode-project-flaky-tests}

> [!WARNING]
> **要求**
>
> - 已配置 <.localized_link href="/guides/features/test-insights/xcode">Xcode 测试洞察</.localized_link>（自动生成的 Scheme 包含 `tuist inspect test` 后置操作；自定义 Scheme 需要手动添加）。

不稳定测试是指在使用相同代码多次运行时产生不同结果（通过或失败）的测试。它们会削弱你对测试套件的信任，并浪费开发人员排查误报失败的时间。Tuist 会自动检测不稳定测试，并帮助你随时间跟踪它们。

![不稳定测试页面](/images/guides/features/test-insights/flaky-tests-page.png)

## 不稳定检测的工作原理 {#how-it-works}

Tuist 通过两种方式检测不稳定测试：

### 测试重试 {#test-retries}

当你使用重试功能运行测试时，Tuist 会分析每次尝试的结果。如果某个测试在某些尝试中失败而在其他尝试中通过，它会被标记为不稳定。

通过 `tuist test` 传递 `-retry-tests-on-failure` 或 `-test-iterations`：

```sh
tuist test --scheme MyScheme -- -retry-tests-on-failure -test-iterations 3
```

![不稳定测试用例详情](/images/guides/features/test-insights/flaky-test-case-detail.png)

### 跨运行检测 {#cross-run-detection}

即使没有测试重试，Tuist 也可以通过比较同一提交和同一 Scheme 的不同 CI 运行的结果来检测不稳定测试。如果某个测试在一次 CI 运行中通过，但在针对同一提交和 Scheme 的另一次运行中失败，则这两次运行都会被标记为不稳定。

Scheme 是比较键的一部分，因为同一个测试在不同 Scheme 下的行为可能具有确定性的差异——例如，仅对特定模拟器目标有效的快照测试，或使用不同标志编译的测试目标。同一提交在不同 Scheme 上的两次运行被视为单独的执行变体，不会互相标记为不稳定。

这对于捕获那些失败频率不足以被重试捕获，但仍会导致间歇性 CI 失败的不稳定测试特别有用。

## 管理不稳定测试 {#managing-flaky-tests}

### 自动清除

检测和清除通过项目上的 **自动化警报** 运行。每个项目都有一个默认的“不稳定测试检测”自动化，其 *触发器* 将测试标记为不稳定，而其 *恢复* 会在测试在配置的恢复窗口（默认 **14 天**）内未重新触发后清除标记。在 **设置 → 自动化** 下编辑它以更改恢复窗口、交换恢复操作（例如也取消隔离），或完全禁用恢复，以便测试保持标记为不稳定，直到你手动清除它们。

### 手动管理

你还可以从测试用例详情页面手动将测试标记为不稳定或取消标记。这在以下情况下很有用：
- 你希望在修复已知不稳定测试的同时确认它
- 由于基础设施问题，测试被错误地标记

## 隔离不稳定测试 {#quarantining}

隔离可以将不稳定测试隔离开来，使其在你修复时不会阻塞 CI。默认情况下，这是一个 **手动操作**——你可以从仪表板中的测试用例详情页面进行隔离、取消隔离和切换模式——但你也可以将其连接到 **设置 → 自动化** 下的 **自动化警报**，以便当测试超过不稳定性阈值时自动静音（或跳过），并在恢复时取消隔离。每次转换，无论是手动还是自动，都会记录在测试用例的审计日志中。

被隔离的测试处于两种模式之一：

- **静音**：测试仍然运行，但 `tuist test` 会屏蔽失败。失败仍然会输入不稳定测试检测器，因此你可以在不破坏构建的情况下继续观察测试。选择此模式用于你正在积极调查的测试。
- **跳过**：xcodebuild 接收 `-skip-testing <identifier>`，因此测试永远不会启动。它不会产生新结果，并从不稳定测试仪表板中消失，直到你重新启用它。当测试损坏、缓慢或不稳定性如此持久以至于运行它只是浪费 CI 分钟数时，请选择此模式。

### 为什么被隔离的测试可能显示为通过 {#quarantined-passing}

- **静音测试** 仍然执行。失败的静音测试在测试用例运行中被记录为 **失败** 并标记为不稳定——每个测试的状态不会被重写。被覆盖的是 **整体测试运行**：如果运行中每个失败的测试用例都被静音，则整个运行报告为通过，因此静音失败不会破坏 CI。
- **跳过的测试** 根本不运行，因此仪表板继续显示测试最后一次实际执行的状态——该快照可能已有数周之久。

### 运行测试 {#running-tests}

`tuist test` 自动尊重这两种模式：

```sh
tuist test
```

跳过的测试作为 `-skip-testing` 传递给 xcodebuild 且永远不会启动。静音测试正常运行；如果它们失败，失败会在 resulting 构建状态中被屏蔽。

要完全绕过隔离并运行所有内容，包括静音和跳过的测试：

```sh
tuist test --skip-quarantine
```

## 压力测试新测试 {#stress-testing-new-tests}

压力门控会重新运行你的分支添加的测试用例，每个用例在新进程中运行多次，并报告那些结果不稳定的用例。你可以在引入它的拉取请求上看到新的不稳定测试，而不是几周后。

当测试用例在过去 90 天内未在项目的默认分支上运行，或在随后合并到该分支的提交上未运行时，它被视为新测试用例。使用合并队列时，队列运行的测试用例在队列的提交合并后即被知晓，如果队列丢弃它，则保持为新测试用例。提交通过 Tuist 在 CI 上收集的 <.localized_link href="/guides/features/test-insights/xcode#git-history">Git 历史</.localized_link> 进行匹配。

### 启用它

门控默认关闭。设置一种模式：

- **`report`**：警告每个不稳定测试用例。运行仍以其自身结果退出。
- **`enforce`**：不稳定测试用例会导致运行失败，退出代码与失败的测试相同。

在这两种模式下，<.localized_link href="/guides/features/selective-testing/generated-xcode-project">选择性测试</.localized_link> 不会在下一次运行中跳过包含新的不稳定测试用例的测试目标。该目标会再次运行，门控会再次对该测试用例进行压力测试，直到它通过所有重新运行。

先从 `report` 开始使用几周，看看 `enforce` 会阻止哪些内容。

将其放在透传参数之前，或设置 `TUIST_TEST_STRESS_NEW_TESTS` 以针对每个 CI 通道调整模式：

```sh
tuist test --stress-new-tests report
```

### 每个测试重新运行的次数

这取决于测试用例在首次运行时花费的时间：

| 首次运行 | 重新运行次数 |
| --- | --- |
| 最多 5 秒 | 10 |
| 最多 10 秒 | 5 |
| 最多 30 秒 | 3 |
| 最多 5 分钟 | 2 |
| 超过 5 分钟 | 不重新运行 |

重新运行会复用首次运行构建的内容。当达到 200 个测试用例或 10 分钟时（以先到达者为准），运行将停止，并说明触发了哪个限制。

### 门控不运行的情况

- 首次运行已经失败。请先修复这些测试。
- 项目没有默认分支，或者尚未在其上运行任何 CI。
- 超过 30% 的项目测试用例看起来是新的。重新运行这么多用例会得不偿失。在刚刚开始向 Tuist 报告的项目中，或在重命名导致大量测试同时移动后，可能会出现这种情况。

## Slack 通知 {#slack-notifications}

通过在 Slack 集成中设置 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">不稳定测试警报</.localized_link>，在测试变得不稳定时立即收到通知。

## 查询不稳定和隔离状态 {#querying}

### CLI

`tuist test case` 命令树展示了 Tuist 跟踪的关于测试用例的所有信息：

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

所有这些命令都接受 `--json` 以用于脚本编写。

### REST API

相同的数据可通过 HTTP 获取——请参阅 API 参考中的 [测试用例端点](https://tuist.dev/api/docs#tag/test-cases)，了解完整的路由、过滤器和响应字段列表。要更改测试用例的状态（标记或取消标记为不稳定、静音、跳过），请使用 `is_flaky` 或 `state` 发送 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`。相同的更改也可通过 `tuist test case update` 和 `update_test_case` Model Context Protocol 工具实现。
