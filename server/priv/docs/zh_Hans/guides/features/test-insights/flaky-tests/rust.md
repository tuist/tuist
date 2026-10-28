---
{
  "title": "Rust Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and investigate flaky Cargo tests using CI history."
}
---
# Rust 不稳定测试 {#rust-flaky-tests}

Tuist 可以检测不一致的 Cargo 测试结果，并帮助你在 **Tests → Flaky Tests** 中调查它们。

> [!IMPORTANT] Requirements
> - 配置 <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>。

## 不稳定检测的工作原理 {#how-it-works}

Tuist 会比较同一提交上的 CI 运行结果。如果一个测试在一次运行中通过而在另一次运行中失败，则可能被标记为不稳定。

通过常用命令报告每次运行：

```sh
tuist cargo test --workspace
```

Cargo 不会自动重试失败的测试。在同一提交上重新运行 CI 作业可以提供另一个结果，用于跨运行检测。

## 管理不稳定测试 {#managing-flaky-tests}

### 自动清除

检测和恢复通过项目的“不稳定测试检测”自动化运行。默认情况下，如果在 14 天内未重新触发，不稳定标志将被清除。你可以在 **Settings → Automations** 下编辑恢复窗口和操作。

### 手动管理

打开 **Tests → Flaky Tests** 以检查测试的历史记录。你可以从其详情页面手动将其标记或取消标记为不稳定。

## 隔离和压力测试 {#quarantine}

Cargo 集成尚未应用隔离：在仪表板中静音或跳过的测试仍会运行，其失败仍会影响结果。它也不会对新测试进行压力测试。在调查失败测试时，使用 Cargo 测试过滤器来重复运行该测试：

```sh
tuist cargo test -p store rejects_invalid_token
```

## Slack 通知 {#notifications}

配置 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">Slack flaky test alerts</.localized_link>，以便在测试变得不稳定时通知你的团队。
