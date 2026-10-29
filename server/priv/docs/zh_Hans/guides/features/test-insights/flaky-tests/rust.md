---
{
  "title": "Rust 不稳定测试",
  "titleTemplate": ":title · 不稳定测试 · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "利用 CI 历史记录检测并排查不稳定的 Cargo 测试。"
}
---
# Rust 不稳定测试 {#rust-flaky-tests}

Tuist 可以检测不一致的 Cargo 测试结果，并帮助你在 **测试 → 不稳定测试** 中调查它们。

> [!IMPORTANT] Requirements
> - 配置 <.localized_link href="/guides/features/test-insights/rust">Rust 测试洞察</.localized_link>。

## 不稳定检测的工作原理 {#how-it-works}

Tuist 会比较同一提交上的 CI 运行结果。如果在一次运行中通过而在另一次运行中失败，该测试可能会被标记为不稳定。

通过常规命令报告每次运行：

```sh
tuist cargo test --workspace
```

Cargo 不会自动重试失败的测试。在同一提交上重新运行 CI 作业可提供另一个结果，用于跨运行检测。

## 管理不稳定测试 {#managing-flaky-tests}

### 自动清除

检测和恢复通过项目的“不稳定测试检测”自动化运行。默认情况下，如果 14 天内未重新触发，不稳定标志将清除。在 **设置 → 自动化** 下编辑恢复窗口和操作。

### 手动管理

打开 **测试 → 不稳定测试** 以检查测试的历史记录。你可以从其详情页面手动将其标记或取消标记为不稳定。

## 隔离和压力测试 {#quarantine}

从其详情页面静音或跳过测试，或在 **设置 → 自动化** 中配置隔离。下一次 `tuist cargo test` 将获取项目当前的隔离状态：

- **静音** 测试仍会运行并报告其实际结果，但其失败不会导致命令失败。其他测试失败、编译错误、崩溃和不完整的结果仍会正常导致失败。
- **跳过** 测试将被排除在执行之外，并报告为已隔离的跳过。匹配包括包、目标、Rust 模块路径和测试名称，因此名称相似的测试保持独立。

静音会保留所选的工作区包和功能，并运行所有选定的目标，即使静音的目标失败也是如此。跳过隔离需要选择一个包：使用 `tuist cargo test -p store` 而不是多包工作区命令。Tuist 拒绝多包跳过，因为缩小命令范围可能会改变 Cargo 的统一依赖功能。

隔离也适用于 <.localized_link href="/guides/features/test-sharding/rust">分片的 Cargo 运行</.localized_link>。如果 Tuist 无法获取状态，它会发出警告并在没有隔离的情况下运行；失败不会被抑制。若要故意在没有隔离的情况下运行：

```sh
TUIST_TEST_SKIP_QUARANTINE=1 tuist cargo test --workspace
```

强制执行需要标准的 libtest 测试 harness 和捕获的默认输出。当需要应用隔离时，带有安静、详细、备用格式或未捕获输出的命令会失败。如果目标归属不明确，请使用 `-p <package>` 选择确切的工作区包。不支持自定义 harness、包/目标名称通配符和未解析的包选择。文档测试也可以被静音或跳过，但 Rustdoc 的测试过滤无法区分每对可能的示例名称。如果跳过某个示例也会跳过已启用的示例，或者部分文档测试排除使用 `--exact`，Tuist 会因诊断而失败，而不是执行被跳过的示例或静默省略已启用的测试；在调查期间使用上述覆盖。

Tuist 不对新的 Cargo 测试进行压力测试。使用 Cargo 测试过滤器在调查失败测试时重复运行它：

```sh
tuist cargo test -p store rejects_invalid_token
```

## Slack 通知 {#notifications}

配置 <.localized_link href="/guides/integrations/slack#flaky-test-alerts">Slack 不稳定测试警报</.localized_link>，以便在测试变得不稳定时通知你的团队。
