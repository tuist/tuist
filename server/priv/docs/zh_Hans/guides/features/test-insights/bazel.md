---
{
  "title": "Bazel 测试洞察",
  "titleTemplate": ":title · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 仪表板中跟踪 Bazel 测试分析数据，以监控测试性能和可靠性。"
}
---
# Bazel 测试洞察 {#bazel-test-insights}

> [!IMPORTANT]
> **要求**
>
> - 通过 `tuist bazel setup` 连接的 Bazel 工作区，如 <.localized_link href="/guides/get-started/bazel-project">Bazel 项目入门</.localized_link> 中所述。

`tuist bazel setup` 会在 `.bazelrc.tuist` 中配置每个测试用例的报告，因此普通的 `bazel test` 会将单个测试用例报告到与其他构建系统相同的仪表板：

```bash
bazel test //app:tests
```

要同时应用 <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">隔离</.localized_link>，请改用 Tuist 包装器运行测试。`--` 之后的参数会转发给 `bazel test`：

```bash
tuist bazel test -- //app:tests
```

## 跟踪内容 {#what-is-tracked}

Tuist 解析 `test.xml` 报告并捕获 Bazel 为每个测试目标生成的 `test.log` 输出，然后将它们汇总到共享的测试运行模型中。每次运行都会记录：

- 单个测试用例的通过、失败和跳过状态，以及持续时间。
- 测试目标、类和套件结构。
- 当 Bazel 配置为重试不稳定测试时的重试尝试。
- 从目标的 `test.log` 中捕获的失败输出。

对于 Bazel，**测试运行**、**测试用例** 和单个测试页面的工作方式与其他构建系统相同。

## 生成每个测试用例的 JUnit 报告 {#per-case-junit-reports}

每个测试用例的行取决于测试目标在 Bazel 提供的 `$XML_OUTPUT_FILE` 路径下写入 JUnit `test.xml`。如果运行器未写入该文件，Bazel 会回退到以目标命名的合成单用例报告，而 Tuist 会为每个目标显示一行（在测试用例列表中标记为 **Bazel 目标**），原始 `test.log` 仍可在运行页面上查看。

大多数 Bazel 测试规则已经生成真正的 `test.xml`：

- `java_test` 和 `kt_jvm_test`：内置 JUnit。
- 使用 GoogleTest 的 `cc_test`：当针对较新的 gtest 编译时，运行器会写入 JUnit；较旧的设置需要 `--gtest_output=xml:$XML_OUTPUT_FILE`。
- `py_test`：将 pytest 与 `--junitxml=$XML_OUTPUT_FILE` 一起使用，或使用 `rules_python` pytest 运行器。
- `go_test`：将 `go test -json` 通过管道传递给 `gotestsum --junitfile=$XML_OUTPUT_FILE`，或使用发出 JUnit 的辅助工具进行包装。

来自 `rules_rust` 和 `rules_rs` 的 `rust_test` 运行标准的 `libtest` 测试框架，该框架在稳定版 Rust 上不会写入 JUnit。使用脚本包装测试目标，该脚本解析 `libtest` 输出并将 JUnit 写入 `$XML_OUTPUT_FILE`；这样你可以在 Tuist 中保留每个测试用例的行，而同一次运行仍保持为单个 Bazel 测试目标。

## 测试标识 {#test-identity}

测试用例通过目标标签、类名（回退到套件名称）和测试名称进行标识。这使得不同类中同名方法保持分离。使用不同外部套件名称的旧报告会将其历史记录保留在旧标识下；应用于旧标识的状态更改需要重新应用到新标识，并且当失败匹配旧标识时，命令会发出警告，以便你知道要迁移哪个策略。

## 提供 CI 上下文 {#providing-ci-context}

Tuist 从 Bazel 的构建元数据中读取 git 提交和分支信息，因此可以跨环境比较同一提交上的运行。大多数持续集成系统已设置这些信息；如果你的系统未设置，请显式传递：

```bash
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

同样的 `--build_metadata` 标志正是 <.localized_link href="/guides/features/build-insights/bazel#custom-metadata">Bazel 构建洞察</.localized_link> 页面描述的用于标记调用的标志，因此一组标志即可覆盖这两个界面。

## 不稳定测试和隔离 {#flaky-tests-and-quarantine}

重试、跨运行的不稳定检测以及每个测试用例的隔离（静音和跳过）都通过 `tuist bazel test` 生效。有关完整工作流程，请参阅 <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">Bazel 不稳定测试</.localized_link>。

## 数据保留 {#data-retention}

Tuist 会保留产生测试运行的 Bazel 调用、其日志以及待处理的测试摄入记录 90 天。测试用例及其运行历史使用与其他构建系统相同的模型，不受该时间窗口限制。有关完整政策，请参阅 <.localized_link href="/guides/server/data-retention">数据保留</.localized_link>。
