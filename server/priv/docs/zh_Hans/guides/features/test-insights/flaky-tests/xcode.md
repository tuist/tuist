---
{
  "title": "Xcode 不稳定测试",
  "titleTemplate": ":title · 不稳定测试 · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 检测、管理和隔离 Xcode 项目中的不稳定测试。"
}
---
# Xcode 不稳定测试 {#xcode-flaky-tests}

> [!WARNING]
> **要求**
>
> - 已配置 <.localized_link href="/guides/features/test-insights/xcode">Xcode 测试洞察</.localized_link>。Tuist 会根据每次测试运行上传的测试洞察事件检测不稳定测试。

不稳定测试是指在相同代码下多次运行时产生不同结果（通过或失败）的测试。它们会削弱你对测试套件的信任，并浪费开发人员排查误报失败的时间。Tuist 会自动检测不稳定测试，并帮助你随时间跟踪它们。

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

### 跨运行检测 {#cross-run-detection}

即使没有测试重试，Tuist 也可以通过比较同一提交、同一 scheme 和同一报告目标（设备名称、平台和操作系统版本）的不同 CI 运行的结果来检测不稳定测试。如果某个测试在一个匹配的 CI 运行中通过，但在另一个中失败，则失败的执行会被标记为不稳定。无论哪个结果先到达，此方法都有效。

同一个测试在不同 scheme 或目标上的表现可能始终不同。例如，在 iOS 26 上通过而在 iOS 27 上失败并不构成不稳定性。来自不同 scheme、设备、平台或操作系统版本的结果不会相互标记为不稳定。

无法归因到具体目标的结果会与其他未归因的结果进行比较，并与已知目标的结果分开处理。这包括缺少或不完整的目标元数据的报告，以及包含多个不同目标的报告，因为单个测试结果尚无法归因到具体目标。该组内环境之间的差异仍可能导致错误的不稳定分类。基于重试的检测仍然适用。现有的历史不稳定分类保持不变。

这对于捕捉那些失败频率不足以被重试捕获、但仍会导致间歇性 CI 失败的不稳定测试特别有用。

## 管理不稳定测试 {#managing-flaky-tests}

### 自动清除

检测和清除通过项目上的 **自动化警报** 运行。每个项目都会获得一个默认的“不稳定测试检测”自动化，其 *触发器* 会将测试标记为不稳定，而其 *恢复* 会在测试经过配置的恢复窗口（默认 **14 天**）且未重新触发后清除标记。在 **设置 → 自动化** 下进行编辑，以更改恢复窗口、替换恢复操作（例如同时解除隔离），或完全禁用恢复，使测试保持标记为不稳定状态，直到你手动清除。

### 手动管理

你还可以在测试用例详情页面手动将测试标记或取消标记为不稳定。这在以下情况下很有用：
- 你希望在修复已知不稳定测试的同时予以确认
- 由于基础设施问题导致测试被错误标记

## 隔离不稳定测试 {#quarantining}

隔离可以将不稳定测试隔离开来，使其在你修复期间不会阻塞 CI。默认情况下，这是一个 **手动操作** — 你可以在仪表板的测试用例详情页面进行隔离、解除隔离和切换模式 — 但你也可以将其连接到 **设置 → 自动化** 下的 **自动化警报**，以便在测试超过不稳定性阈值时自动静音（或跳过），并在恢复时解除隔离。每次转换，无论是手动还是自动，都会记录在测试用例的审计日志中。

被隔离的测试处于以下两种模式之一：

- **静音**：测试仍然运行，但 `tuist xcodebuild test` 会屏蔽失败。失败仍会提供给不稳定测试检测器，因此你可以继续观察测试而不会中断构建。选择此模式用于你正在积极调查的测试。
- **跳过**：xcodebuild 会收到 `-skip-testing <identifier>`，因此测试永远不会启动。它不会产生新结果，并从不稳定测试仪表板中消失，直到你重新启用它。当测试损坏、缓慢或不稳定性持续存在以至于运行它只是浪费 CI 分钟数时，请选择此模式。

### 为什么被隔离的测试可能显示为通过 {#quarantined-passing}

- **静音测试** 仍然执行。失败的静音测试在测试用例运行中被记录为 **失败** 并标记为不稳定 — 每个测试的状态不会被重写。被覆盖的是 **整体测试运行**：如果运行中每个失败的测试用例都被静音，则整个运行会被报告为通过，因此静音失败不会中断 CI。
- **跳过的测试** 根本不会运行，因此仪表板会继续显示测试最后一次实际执行的状态 — 该快照可能已是数周前的数据。

### 运行测试 {#running-tests}

`tuist xcodebuild test` 是一个直通包装器，会自动尊重这两种模式。使用它的方式与调用 xcodebuild 相同：

```sh
tuist xcodebuild test -scheme MyScheme
```

跳过的测试会作为 `-skip-testing <identifier>` 附加到你的 xcodebuild 调用中，并且永远不会启动。静音测试正常运行；如果它们失败，失败会在生成的构建状态中被屏蔽。

#### 绕过隔离

`tuist xcodebuild test` 接受 `--skip-quarantine` 以运行所有内容，包括静音和跳过的测试：

```sh
tuist xcodebuild test --skip-quarantine -scheme MyScheme
```

#### 直接调用 xcodebuild

如果你无法通过 `tuist xcodebuild test`，请使用 `tuist test case list` 自行将被隔离的测试扩展为 `-skip-testing` 参数：

```sh
xcodebuild test \
  -scheme MyScheme \
  $(tuist test case list --quarantined --skip-testing)
```

这是在 `tuist xcodebuild test` 之外的安全默认值：静音测试的失败屏蔽仅在你通过该命令时发生，因此跳过这两种模式可以避免虚假的 CI 失败。如果你需要更精细的控制，请改用 `tuist xcodebuild test`。

## 对新测试进行压力测试 {#stress-testing-new-tests}

压力测试门控会重新运行你的分支新增的测试用例，每个用例在全新进程中运行多次，并报告其中不稳定的用例。你可以在引入该不稳定测试的拉取请求上立即看到它，而不是几周后才发现。

如果测试用例在过去 90 天内未在项目的默认分支上运行过 CI，或者未在已合并到默认分支的提交上运行过，则视为新测试用例。使用合并队列时，一旦队列的提交合并，队列运行的测试用例就会被识别；如果队列丢弃了该测试用例，它仍保持为新测试用例。提交通过 Tuist 在 CI 中收集的 <.localized_link href="/guides/features/test-insights/xcode#git-history">Git 历史</.localized_link> 进行匹配。

### 启用方法

门控默认关闭。设置一种模式：

- **`report`**：对每个不稳定测试用例发出警告。运行仍按其自身结果退出。
- **`enforce`**：不稳定测试用例会令运行失败，退出码与失败的测试相同。

先使用 `report` 几周，看看 `enforce` 会拦截哪些情况。

将其放在直通参数之前传递，或设置 `TUIST_TEST_STRESS_NEW_TESTS` 以按 CI 通道调整模式：

```sh
tuist xcodebuild test --stress-new-tests report -scheme MyScheme
```

### 每个测试的重运行次数

取决于测试用例在首次运行中的耗时：

| 首次运行 | 重运行次数 |
| --- | --- |
| 最多 5 秒 | 10 |
| 最多 10 秒 | 5 |
| 最多 30 秒 | 3 |
| 最多 5 分钟 | 2 |
| 超过 5 分钟 | 不重运行 |

重运行会复用首次运行构建的内容。运行会在达到 200 个测试用例或 10 分钟时停止（以先达到者为准），并说明触发了哪个限制。

### 门控不运行的情况

- 首次运行已经失败。请先修复这些测试。
- 项目没有默认分支，或其上尚未运行过任何 CI。
- 项目中超过 30% 的测试用例看起来是新的。重运行这么多用例会得不偿失。在刚开始向 Tuist 报告的项目，或在一次重命名中移动了大量测试的项目中，可能会出现这种情况。

## Slack 通知 {#slack-notifications}

通过在 Slack 集成中设置 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">不稳定测试警报</.localized_link>，在测试变为不稳定时立即收到通知。

## 查询不稳定和隔离状态 {#querying}

### CLI

`tuist test case` 命令树会展示 Tuist 跟踪的测试用例的所有信息：

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

所有这些命令都接受 `--json` 以便脚本化。

### REST API

同样的数据可通过 HTTP 获取 — 请参阅 API 参考中的 [测试用例端点](https://tuist.dev/api/docs#tag/test-cases)，了解完整的路由、过滤器和响应字段列表。要更改测试用例的状态（标记或取消标记为不稳定、静音、跳过），请使用 `is_flaky` 或 `state` 发送 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`。同样的更改也可通过 `tuist test case update` 以及 `update_test_case` Model Context Protocol 工具实现。
