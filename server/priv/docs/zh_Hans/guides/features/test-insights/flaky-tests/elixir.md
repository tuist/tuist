---
{
  "title": "Elixir 不稳定测试",
  "titleTemplate": ":title · 不稳定测试 · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "检测并管理使用 Mix 构建的 Elixir 项目中的不稳定测试。"
}
---
# Elixir 不稳定测试 {#elixir-flaky-tests}

不稳定测试是指在使用相同代码多次运行时产生不同结果（通过或失败）的测试。它们会削弱你对测试套件的信任，并浪费开发人员排查误报失败的时间。Tuist 会自动检测不稳定测试，并帮助你随时间跟踪它们。

> [!IMPORTANT] REQUIREMENTS
> - 完成<.localized_link href="/guides/get-started/elixir-project">共享 Elixir 设置</.localized_link>以报告你的测试运行

![Phoenix 应用的不稳定测试](/images/guides/features/elixir/flaky-tests.png)

## 不稳定检测的工作原理 {#how-it-works}

Tuist 通过两种方式检测不稳定测试：

### 测试重试 {#test-retries}

ExUnit 每次只运行每个测试一次，因此间歇性失败的测试看起来与损坏的测试无异。启用重试后，Hex 包会重新运行失败的测试，最多达到你设置的次数。在重试中通过的测试会被标记为不稳定，如果所有失败的测试最终都通过，则本次运行成功。

默认情况下重试处于关闭状态。将 `test_retries` 添加到 `mix.exs` 中现有的 Tuist 选项以启用它们：

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

或者对于单次运行，使用标志或环境变量：

```bash
mix test --retries 2
TUIST_TEST_RETRIES=2 mix test
```

标志优先于环境变量，环境变量优先于 `mix.exs`。

只有失败的测试会再次运行，方式与 `mix test --failed` 运行它们的方式相同，仪表板会显示每次测试尝试及其耗时。因 `--max-failures` 而提前停止的运行不会重试。如果运行中所有失败的测试都超时，也不会重试，因为每次重试都会再次等待所有超时。使用 `--warnings-as-errors` 时也会跳过重试，此时 `mix test` 不再强制执行；从 umbrella 项目的根目录运行时也会跳过重试；请在其中一个应用程序内部运行测试以进行重试。

![不稳定的 ExUnit 测试及其历史记录](/images/guides/features/elixir/flaky-test-case.png)

### 跨运行检测 {#cross-run-detection}

即使没有测试重试，Tuist 也可以通过比较同一提交在不同 CI 运行中的结果来检测不稳定测试。如果一个测试在一次 CI 运行中通过，但在同一提交的另一次运行中失败，则两次运行都会被标记为不稳定。

这对于捕获那些失败频率不足以被重试捕获、但仍会导致间歇性 CI 失败的不稳定测试特别有用。

## 管理不稳定测试 {#managing-flaky-tests}

### 自动清除

检测和清除通过项目上的**自动化警报**运行。每个项目都有一个默认的“不稳定测试检测”自动化，其*触发器*会将测试标记为不稳定，而其*恢复*会在测试经过配置的恢复窗口（默认**14 天**）且未重新触发后清除该标记。在**设置 → 自动化**下编辑它以更改恢复窗口或完全禁用恢复，以便测试保持标记为不稳定，直到你手动清除它们。

### 手动管理

你还可以在测试用例详情页面手动将测试标记为不稳定或取消标记。这在以下情况很有用：
- 你想在修复已知不稳定测试时予以确认
- 测试因基础设施问题被错误标记

## 隔离不稳定测试 {#quarantining}

隔离可以防止不稳定测试在你修复期间阻塞 CI。在仪表板的测试页面上，将其状态更改为**静音**或**跳过**，或在**设置 → 自动化**下配置一个自动化，当测试变得不稳定时将其静音或跳过，并在其恢复后再次启用。在运行测试之前，`mix test` 会读取项目中的每个隔离测试并应用它们：

- **静音**：测试会运行，其失败仍会被报告，但如果运行中唯一的失败是静音测试，则运行通过。重试仍会重新运行失败的静音测试，因此不稳定的测试可以通过并被报告为不稳定。
- **跳过**：测试不会运行。`mix test` 会在运行开始前列出跳过的测试。

```text
Tuist: skipping 1 quarantined test:
  MyApp.CheckoutTest: create_order/2 times out
Tuist: 1 muted test run, and their failures do not fail the run.
```

当任何非静音测试失败，或因 `--max-failures` 导致 ExUnit 提前停止时，运行会像往常一样失败。

> [!WARNING]
> **限制**
>
> - 只有较新版本的 Hex 包才会应用隔离。较早版本会像其他测试一样运行静音和跳过的测试，因此静音测试的失败仍会导致运行失败。在依赖此功能之前，请更新 `tuist_ex`。
> - 使用 `--warnings-as-errors` 或从 umbrella 项目的根目录运行时，不会应用静音测试。它们的失败会导致运行失败。请改为在 umbrella 的每个应用程序内部运行测试。
> - 跳过是根据测试的 describe 块和名称进行匹配，而不是根据其模块。另一个模块中具有相同 describe 块和名称的测试也会被跳过。请参阅[跳过如何选择测试](#how-skipping-selects-tests)。
> - 当你使用 `--only`、`--include` 或 `path:line` 选择跳过的测试时，或者当测试未使用 `test` 声明时（例如 StreamData `property`），它仍会运行。
> - 如果 `mix test` 无法读取隔离的测试，它将运行每个测试并统计每次失败。
> - 读取隔离的测试需要凭据，即使是公共项目也是如此。没有 `TUIST_TOKEN`、`mix tuist.login` 会话或持续集成身份令牌运行的不会应用任何隔离。这包括来自 fork 的拉取请求，它们通常在没有密钥的情况下运行。
> - 使用 `--cover` 时，跳过的测试计为已移除：仅由它覆盖的行会被报告为未覆盖。
>
> `mix test` 会在摘要之后列出被错误遗漏的跳过测试以及无论如何都运行的跳过测试。

### 跳过如何选择测试 {#how-skipping-selects-tests}

跳过的测试会通过基于其全名的 ExUnit 过滤器被排除，例如 `--exclude "test:test create_order/2 times out"`。ExUnit 过滤器无法同时匹配模块，因此：

- 另一个模块中具有相同 describe 块和名称的测试也会被排除。`mix test` 会在运行后列出这些测试。
- 使用 `--only`、`--include` 或 `path:line` 选择的测试即使被跳过也会运行，因为 ExUnit 会在排除过滤器之后应用包含过滤器。未使用 `test` 声明的测试（例如 StreamData `property`）也是如此。`mix test` 会在运行后列出这些测试。

### 再次运行隔离的测试 {#running-quarantined-tests-again}

传入 `--no-quarantine` 以运行每个测试并统计每次失败，例如用于验证修复：

```bash
mix test --no-quarantine
```

在测试页面将其状态恢复为**启用**，以便在后续运行中包含它。跳过的测试在再次运行之前不会产生新结果。

如果 `mix test` 无法读取隔离的测试，它会打印警告并运行所有测试而不应用隔离。如果没有凭据或未配置项目，它会运行所有测试且不显示警告。

Hex 包尚不对新测试进行压力测试。

## Slack 通知 {#slack-notifications}

通过在 Slack 集成中设置<.localized_link href="/guides/integrations/slack#flaky-test-alerts">不稳定测试提醒</.localized_link>，在测试变得不稳定时立即收到通知。

## 查询不稳定状态 {#querying}

数据可通过 HTTP 获取。请参阅 API 参考中的[测试用例端点](https://tuist.dev/api/docs#tag/test-cases)，查看完整的路由、过滤器和响应字段列表。要将测试用例标记为或取消标记为不稳定，请发送带有 `is_flaky` 的 `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}`，或使用 `update_test_case` Model Context Protocol 工具。
