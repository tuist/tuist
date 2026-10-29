---
{
  "title": "Bazel Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect flaky Bazel tests, mute their failures, and skip quarantined targets."
}
---

# Bazel 不稳定测试 {#bazel-flaky-tests}

`tuist bazel test` 在每次调用前获取 Tuist 的隔离策略，并将其应用于底层的 `bazel test` 运行。

## 应用隔离 {#applying-quarantine}

在测试页面上，将其状态更改为 **已静音**，然后运行：

```sh
tuist bazel test -- //app:tests
```

`--` 之后的参数会转发给 `bazel test`。使用 `--path` 选择项目和工作目录，使用 `--bazel` 选择不同的可执行文件，例如 `bazelisk`。普通的 `bazel test` 仍然报告测试结果，但不会获取或强制执行 Tuist 隔离策略。

隔离不需要命名的 Bazel 配置或重试。**不稳定测试**、**已隔离测试**和单个测试页面支持与其他构建系统相同的手动状态更改。使用 **设置 → 自动化** 配置不稳定性阈值、隔离操作和恢复操作。

### 静音 {#mute}

使用 **静音** 作为主要的隔离工作流。被静音的用例继续运行，其失败仍然可见，健康的兄弟用例仍然影响结果。新的执行提供恢复证据，而不会从目标中排除任何用例。

Tuist 读取临时的本地构建事件文件和引用的 `test.xml` 报告。仅当完整报告将每个失败目标中报告的每个失败归因于一个被静音的用例时，它才会将 Bazel 的测试失败退出状态更改为成功。

构建错误、超时、中断的运行、缺失或格式错误的报告、不完整的事件流以及静音集之外的失败保留 Bazel 的失败状态。本地事件文件限制为 64 MiB，单个报告限制为 5 MiB。Tuist 需要自己的本地构建事件文件来验证静音失败并从过时的跳过目标中恢复，因此显式的 `--build_event_json_file` 不能与活动的静音或跳过用例结合使用。远程构建事件报告仍通过 `tuist bazel setup` 进行配置。

原始的 Bazel 调用和报告保留其实际结果。Tuist 的服务器记录调用开始时用例是否被隔离，即使其状态在报告处理之前发生变化。

### 跳过 {#skip}

仅当您打算排除 **整个 Bazel 目标**（包括该目标内的健康用例）时才使用 **跳过**。将单个用例标记为 **已跳过** 会产生这种目标范围的影响。Bazel 的单个用例过滤语法取决于测试框架，并非普遍支持。因此，Tuist 使用启用了测试套件扩展的本机否定目标模式。显式目标、通配符选择和 `test_suite` 规则内的测试保持 Bazel 的正常选择行为。

该命令获取每个隔离页面并对目标进行去重。如果 Bazel 的完整事件日志在目标配置或执行之前识别出缺失的跳过目标，Tuist 会在警告中指明该目标，并在不包含该过时排除项的情况下重试。原始请求的模式和所有其他排除项都会保留。恢复限制为五次重试；其他加载失败和不完整的证据保留 Bazel 的错误。将过时用例返回到 **已启用** 以永久删除其策略。直接传递目标模式；`--target_pattern_file` 不能与隔离排除项结合使用。如果没有剩余的测试目标，Bazel 保留其正常的“未找到测试”退出状态，这也能捕获意外空的测试选择。

该命令打印每个被排除的目标标签，以便构建日志显示隔离策略排除了哪些目标（包括其健康用例）。

### 再次运行已隔离的测试 {#running-quarantined-tests-again}

要调查或验证修复，请绕过两个隔离策略：

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

将用例返回到 **已启用** 以将其目标包含在后续的正常运行中。跳过的用例在被显式包含之前不会产生新的执行，因此基于成功新运行的自动化需要在恢复它们之前进行一次验证运行。

隔离检索错误会在运行测试之前停止命令。该命令还会拒绝超过 20,000 个用例的策略或超过其绑定大小的目标参数；它从不应用部分策略。当您有意想要在没有策略的情况下运行时，请使用 `--no-quarantine`。

## 可选配置和重试 {#optional-configuration-and-retries}

如果您的仓库在 `.bazelrc` 中定义了名为 `ci` 的配置，您可以使用 `--config=ci` 选择它：

```sh
tuist bazel test -- --config=ci //app:tests
```

这是仓库定义的配置，不是 Tuist 的先决条件。当您的仓库未定义它时，请省略该选项。

重试也是可选的，且独立于隔离。`--flaky_test_attempts=3` 启用每个测试最多 **三次 Bazel 尝试**，而不是三次额外的重试。团队可以将其现有的重试配置保留在 `.bazelrc` 中，或显式传递它：

```sh
tuist bazel test -- --flaky_test_attempts=3 //app:tests
```

对于定义了 `ci` 的仓库，可以组合这些选项：

```sh
tuist bazel test -- --config=ci --flaky_test_attempts=3 //app:tests
```

## 检测不稳定性 {#detecting-flakiness}

Tuist 使用 Bazel 的 `test.xml` 报告中的单个用例来检测连续集成中跨重试以及同一提交和目标选择的多次运行之间的不一致结果。本地运行仍然可见，但不会自动将测试用例标记为不稳定。当您的构建环境尚未发布提交和分支元数据时，请提供这些数据：

```sh
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

必须实际运行重试，Tuist 才能观察其结果。仅凭 Bazel 目标的不稳定摘要无法识别哪个单个用例不稳定。不可用或无法解析的报告无法提供用例级别的证据。

用例通过目标标签、类名（回退到套件名称）和测试名称进行标识。这使得不同类中同名方法保持分离。使用不同外部套件名称的旧报告在旧身份下保留其历史；其隔离状态必须应用于新身份。当失败匹配基于旧套件的静音而不是其当前类身份时，命令会警告需要重新应用哪个策略并保持失败阻塞。策略不会自动转移，因为多个类可能共享旧身份。

请参阅 Bazel 的 [测试过滤器](https://bazel.build/docs/user-manual#test-filter)、[命令行选项](https://bazel.build/reference/command-line-reference) 和 [构建事件描述](https://bazel.build/remote/bep-glossary) 以了解底层行为。
