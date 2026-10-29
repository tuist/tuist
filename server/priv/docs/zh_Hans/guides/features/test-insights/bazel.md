---
{
  "title": "Bazel Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Bazel test analytics in the Tuist dashboard to monitor test performance and reliability."
}
---
# Bazel 测试洞察 {#bazel-test-insights}

通过 Tuist 运行 Bazel 测试，以将数据馈送到与其他构建系统相同的测试仪表板：

```bash
tuist bazel test -- //app:tests
```

`--` 之后的参数会转发给 `bazel test`。使用 `--path` 选择项目和工作目录，并使用 `--bazel` 选择不同的可执行文件，例如 `bazelisk`。普通的 `bazel test` 仍然会报告测试结果，但不会获取或强制执行 Tuist 隔离策略。

> [!NOTE]
> `tuist bazel test` 包装器仅用于 <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">隔离的测试</.localized_link>。常规测试运行的逐用例报告由 `tuist bazel setup` 在 `.bazelrc.tuist` 中设置，因此普通的 `bazel test` 也会报告各个用例。

## 跟踪内容 {#what-is-tracked}

Tuist 解析 `test.xml` 报告并捕获 Bazel 为每个测试目标生成的 `test.log` 输出，然后将它们汇总到共享的测试运行模型中。每次运行都会记录：

- 各个测试用例的通过、失败和跳过状态，以及持续时间。
- 测试目标、类和套件结构。
- 当 Bazel 配置为重试不稳定测试时的重试尝试。
- 从目标的 `test.log` 中捕获的失败输出。

**测试运行**、**测试用例** 和单个测试页面对于 Bazel 的工作方式与其他构建系统相同。

## 生成逐用例 JUnit 报告 {#per-case-junit-reports}

逐用例行取决于测试目标是否在 Bazel 提供的 `$XML_OUTPUT_FILE` 路径处写入 JUnit `test.xml`。当运行器未写入时，Bazel 会回退到以目标命名的合成单用例报告，并且 Tuist 会为每个目标显示一行（在测试用例列表中标记为 **Bazel 目标**），原始 `test.log` 仍可在运行页面上查看。

大多数 Bazel 测试规则已经生成真实的 `test.xml`：

- `java_test` 和 `kt_jvm_test`：JUnit 是内置的。
- `cc_test` 与 GoogleTest：当针对较新的 gtest 编译时，运行器会写入 JUnit；较旧的设置需要 `--gtest_output=xml:$XML_OUTPUT_FILE`。
- `py_test`：使用带有 `--junitxml=$XML_OUTPUT_FILE` 的 pytest，或使用 `rules_python` pytest 运行器。
- `go_test`：通过 `gotestsum --junitfile=$XML_OUTPUT_FILE` 管道传输 `go test -json`，或使用发出 JUnit 的辅助程序进行包装。

来自 `rules_rust` 和 `rules_rs` 的 `rust_test` 运行标准的 `libtest` 测试 harness，它在稳定版 Rust 上不会写入 JUnit。使用一个脚本包装测试目标，该脚本解析 `libtest` 输出并将 JUnit 写入 `$XML_OUTPUT_FILE`；这样你可以在 Tuist 中保留逐用例行，并且同一次运行仍保持为单个 Bazel 测试目标。

## 测试身份标识 {#test-identity}

用例通过目标标签、类名（回退到套件名称）和测试名称进行标识。这使得不同类中同名方法保持分离。使用不同外部套件名称的旧报告会将其历史记录保留在旧身份下；应用于旧身份的状态更改需要重新应用于新身份，并且当失败匹配旧身份时，命令会警告你，以便你知道要迁移哪个策略。

## 提供 CI 上下文 {#providing-ci-context}

Tuist 从 Bazel 的构建元数据中读取 git 提交和分支信息，以便可以跨环境比较同一提交的运行。大多数持续集成系统已经设置了这些信息；如果你的系统没有，请显式传递它们：

```bash
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

同样的 `--build_metadata` 标志就是 <.localized_link href="/guides/features/build-insights/bazel#custom-metadata">Bazel 构建洞察</.localized_link> 页面描述的用于标记调用的内容，因此一组标志即可覆盖这两个方面。

## 不稳定测试和隔离 {#flaky-tests-and-quarantine}

重试、跨运行不稳定检测以及逐用例隔离（静音和跳过）都通过 `tuist bazel test` 工作。请参阅 <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">Bazel 不稳定测试</.localized_link> 了解完整工作流程。

## 数据保留 {#data-retention}

Tuist 保留生成测试运行的 Bazel 调用、其日志以及待处理的测试摄取记录 90 天。测试用例及其运行历史使用与其他构建系统相同的模型，不受该时间窗口限制。请参阅 <.localized_link href="/guides/server/data-retention">数据保留</.localized_link> 了解完整政策。
