---
{
  "title": "Bazel 不稳定测试",
  "titleTemplate": ":title · 不稳定测试 · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "检测不稳定的 Bazel 测试，屏蔽其失败结果，并跳过隔离的目标。"
}
---

# Bazel 不稳定测试 {#bazel-flaky-tests}

`tuist bazel test` 会在每次调用前获取 Tuist 的隔离策略，并将其应用于底层的 `bazel test` 运行。

## 应用隔离 {#applying-quarantine}

在测试页面中，将其状态更改为 **已静音**，然后运行：

```sh
tuist bazel test -- //app:tests
```

`--` 之后的参数会转发给 `bazel test`。使用 `--path` 选择项目和工作目录，使用 `--bazel` 选择不同的可执行文件（例如 `bazelisk`）。普通的 `bazel test` 仍会报告测试结果，但不会获取或强制实施 Tuist 隔离策略。

隔离既不需要命名的 Bazel 配置，也不需要重试。**不稳定测试**、**已隔离测试**以及单个测试页面支持与其他构建系统相同的手动状态更改。使用 **设置 → 自动化** 来配置不稳定性阈值、隔离操作和恢复操作。

### 静音 {#mute}

将 **静音** 作为主要的隔离工作流。被静音的用例会继续运行，其失败仍然可见，健康的兄弟用例仍会影响结果。新的执行为恢复提供证据，同时不会从目标中排除任何用例。

Tuist 读取临时的本地构建事件文件和引用的 `test.xml` 报告。仅当完整报告将每个失败目标中的所有报告失败归因于某个被静音的用例时，它才会将 Bazel 的测试失败退出码改为成功。

构建错误、超时、中断的运行、缺失或格式错误的报告、不完整的事件流，以及静音集合之外的失败都会保留 Bazel 的失败状态。本地事件文件限制为 64 MiB，单个报告限制为 5 MiB。Tuist 需要自己的本地构建事件文件来验证静音失败并从过时的跳过目标中恢复，因此显式的 `--build_event_json_file` 不能与活跃的静音或用例跳过组合使用。远程构建事件报告仍通过 `tuist bazel setup` 进行配置。

原始的 Bazel 调用和报告会保留其实际结果。即使用例状态在报告处理之前发生变化，Tuist 服务器也会记录调用开始时该用例是否已被隔离。

### 跳过 {#skip}

仅在打算排除 **整个 Bazel 目标**（包括该目标内的健康用例）时使用 **跳过**。将单个用例标记为 **已跳过** 会产生这种针对整个目标的效果。Bazel 的单个用例过滤语法取决于测试框架，并非普遍受支持。因此，Tuist 使用启用了测试套件扩展的原生否定目标模式。显式目标、通配符选择以及 `test_suite` 规则中的测试会保持 Bazel 的正常选择行为。

该命令会获取每个隔离页面并对目标去重。如果 Bazel 的完整事件日志在目标配置或执行之前识别出缺失的跳过目标，Tuist 会在警告中指出该目标，并在不包含该过时排除项的情况下重试。原始请求的模式和所有其他排除项都会被保留。恢复最多重试五次；其他加载失败和证据不完整的情况会保留 Bazel 的错误。将过时的用例返回到 **已启用** 以永久移除其策略。直接传递目标模式；`--target_pattern_file` 不能与隔离排除项组合使用。如果没有剩余的测试目标，Bazel 会保留其正常的“未找到测试”退出状态，这也能捕获意外为空的测试选择。

该命令会打印每个被排除的目标标签，以便构建日志显示隔离策略排除了哪些目标（包括它们的健康用例）。

### 再次运行已隔离的测试 {#running-quarantined-tests-again}

要调查或验证修复，请绕过两种隔离策略：

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

将该用例返回到 **已启用**，以将其目标包含在后续的正常运行中。被跳过的用例在被显式包含之前不会产生新的执行，因此基于成功新运行的自动化需要先进行一次验证运行才能恢复它们。

隔离检索错误会在运行测试之前停止命令。该命令还会拒绝超过 20,000 个用例的策略或超出其大小限制的目标参数；它永远不会应用部分策略。当你有意要在没有策略的情况下运行时，请使用 `--no-quarantine`。

## 可选配置和重试 {#optional-configuration-and-retries}

如果你的仓库在 `.bazelrc` 中定义了名为 `ci` 的配置，你可以使用 `--config=ci` 来选择它：

```sh
tuist bazel test -- --config=ci //app:tests
```

这是由仓库定义的配置，不是 Tuist 的先决条件。当你的仓库未定义该配置时，请省略此选项。

重试也是可选的，且独立于隔离。`--flaky_test_attempts=3` 会为每个测试启用最多 **三次 Bazel 尝试**，而不是额外的三次重试。团队可以保留其在 `.bazelrc` 中的现有重试配置，或显式传递它：

```sh
tuist bazel test -- --flaky_test_attempts=3 //app:tests
```

对于定义了 `ci` 的仓库，可以组合这些选项：

```sh
tuist bazel test -- --config=ci --flaky_test_attempts=3 //app:tests
```

## 检测不稳定性 {#detecting-flakiness}

Tuist 使用 Bazel 的 `test.xml` 报告中的单个用例来检测跨重试以及持续集成中同一提交和目标选择的多次运行之间的不一致结果。本地运行仍然可见，但不会自动将测试用例标记为不稳定。当你的构建环境尚未发布提交和分支元数据时，请提供这些信息：

```sh
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

必须实际执行重试，Tuist 才能观察其结果。仅凭 Bazel 目标的不稳定摘要无法确定哪个单个用例不稳定。不可用或无法解析的报告无法提供用例级别的证据。

用例通过目标标签、类名（回退到套件名称）和测试名称来标识。这会将不同类中同名方法区分开来。使用不同外部套件名称的旧报告会在新身份下保留其历史记录；它们的隔离状态必须应用到新身份上。当失败匹配的是基于旧套件的静音而非当前的类身份时，命令会警告需要重新应用哪个策略，并保持失败阻塞。策略不会自动转移，因为多个类可能共享旧身份。

请参阅 Bazel 的 [测试过滤器](https://bazel.build/docs/user-manual#test-filter)、[命令行选项](https://bazel.build/reference/command-line-reference) 和 [构建事件描述](https://bazel.build/remote/bep-glossary) 以了解底层行为。
