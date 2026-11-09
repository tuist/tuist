---
{
  "title": "Bazel 不稳定测试",
  "titleTemplate": ":title · 不稳定测试 · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "检测不稳定的 Bazel 测试，屏蔽其失败结果，并跳过已隔离的目标。"
}
---
# Bazel 不稳定测试 {#bazel-flaky-tests}

> [!IMPORTANT]
> **要求**
>
> - 通过 `tuist bazel setup` 配置<.localized_link href="/guides/features/test-insights/bazel">Bazel 测试洞察</.localized_link>。

<!-- @snippet: ./_intro -->

## 不稳定检测的工作原理 {#how-it-works}

Tuist 利用 Bazel `test.xml` 报告中的各个用例，检测在重试之间以及持续集成中同一提交和目标选择的多次运行之间的不一致结果。本地运行仍然可见，但不会自动将测试用例标记为不稳定。

### 测试重试 {#test-retries}

重试是可选的，且独立于隔离策略。`--flaky_test_attempts=3` 可为每个测试启用最多**三次 Bazel 尝试**，而非额外三次重试。请在 `.bazelrc` 中保留现有的重试配置，或显式传递该配置：

```sh
tuist bazel test -- --flaky_test_attempts=3 //app:tests
```

必须实际执行重试，Tuist 才能观察其结果。仅凭 Bazel 目标的不稳定摘要无法确定哪个具体用例不稳定。

### 跨运行检测 {#cross-run-detection}

比较运行需要提交和分支元数据。当你的构建环境尚未发布这些元数据时，请提供它们：

```sh
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

用例通过目标标签、类名（回退到套件名称）和测试名称进行识别，如<.localized_link href="/guides/features/test-insights/bazel">Bazel 测试洞察</.localized_link>中所述。

<!-- @snippet: ./_managing -->

## 隔离不稳定测试 {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

`tuist bazel test` 会在每次调用前获取隔离策略，并将其应用于底层的 `bazel test` 运行。普通的 `bazel test` 仍会报告测试结果，但不会应用隔离策略：

```sh
tuist bazel test -- //app:tests
```

`--` 之后的参数会转发给 `bazel test`。使用 `--path` 选择项目和工作目录，使用 `--bazel` 选择不同的可执行文件（例如 `bazelisk`）。命名的 Bazel 配置（例如 `--config=ci`）是可选的，工作方式相同。

### 静音 {#mute}

将**静音**作为主要的隔离工作流。被静音的用例会继续运行，其失败仍然可见，健康的兄弟用例仍会影响结果。只有当报告将每个失败目标中的所有失败都归因于静音用例时，Tuist 才会将 Bazel 的测试失败退出码转换为成功。构建错误、超时、中断的运行、缺失或不完整的报告，以及静音集合之外的失败都会保持 Bazel 的失败状态。

### 跳过 {#skip}

跳过按 Bazel 目标生效：跳过一个用例会排除其整个目标（包括健康用例），因为 Bazel 无法为每个测试框架过滤单个用例。除非你打算排除整个目标，否则优先使用**静音**。命令会打印每个被排除的目标标签，以便构建日志显示隔离策略排除了哪些内容。

如果被跳过的目标不再存在，Tuist 会在警告中指出该目标，并在不包含该排除项的情况下运行。将过时的用例返回到**启用**状态以永久移除其策略。如果没有剩余的测试目标，Bazel 将保持其正常的“未找到测试”退出状态。

<!-- @snippet: ./_quarantined-passing -->

### 再次运行已隔离的测试 {#running-quarantined-tests-again}

若要调查或验证修复，请绕过隔离策略：

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

将用例返回到**启用**状态，以便在后续的正常运行中包含其目标。跳过的用例在被显式包含之前不会产生新的执行，因此基于成功新运行的自动化需要在恢复它们之前进行一次验证运行。

### 限制 {#limitations}

- 显式的 `--build_event_json_file` 或 `--target_pattern_file` 不能与活跃的隔离策略结合使用。请直接传递目标模式。
- 如果 Tuist 无法获取隔离策略，命令会在运行测试之前停止。它永远不会应用部分策略。当你有意希望在不使用隔离策略的情况下运行时，请使用 `--no-quarantine`。
- 与较早的基于套件的标识下记录的静音相匹配的失败仍然会阻塞，并且命令会指出需要重新应用的策略。

请参阅 Bazel 的[测试过滤器](https://bazel.build/docs/user-manual#test-filter)、[命令行选项](https://bazel.build/reference/command-line-reference)和[构建事件描述](https://bazel.build/remote/bep-glossary)以了解底层行为。

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
