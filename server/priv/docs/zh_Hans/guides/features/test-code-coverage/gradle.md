---
{
  "title": "Gradle 代码覆盖率",
  "titleTemplate": ":title · 代码覆盖率 · 功能 · 指南 · Tuist",
  "description": "上传使用 JaCoCo 测量的 Gradle 项目测试的代码覆盖率，并按文件、项目和提交跟踪。"
}
---
# Gradle 代码覆盖率 {#gradle-code-coverage}

代码覆盖率告诉你测试执行了代码中的哪些行。Tuist Gradle 插件使用 JaCoCo 测量测试任务的覆盖率，并在每次测试运行时上传。Tuist 会将一个提交的所有运行合并为一个数据，涵盖整个项目、每个 Gradle 项目以及每个文件。仪表板的 **代码覆盖率** 页面按提交显示该数据，并展示每个分支的趋势。

> [!IMPORTANT]
> **要求**
>
> - 已应用 `dev.tuist` Gradle 插件，如 <.localized_link href="/guides/get-started/gradle-project">开始使用 Gradle 项目</.localized_link> 中所述
> - 你的项目位于 Git 仓库中：在非 Git 环境中运行会上传测试结果，但不会上传覆盖率

## 设置 {#setup}

### 开启覆盖率 {#turn-coverage-on}

在 `settings.gradle.kts` 的 `tuist` 块中开启覆盖率：

```kotlin
tuist {
    coverage {
        enabled = true
    }
}
```

或者通过环境变量为单次调用（例如 CI 作业）开启覆盖率，该设置优先于上述配置：

```sh
TUIST_TEST_COVERAGE=1 ./gradlew test
```

开启覆盖率后，插件会将 Gradle 的 `jacoco` 插件应用到每个 JVM 项目。JaCoCo 代理来自你项目的仓库，就像你自己应用该插件一样。如果项目已经配置了 JaCoCo，它将保留原有设置，其报告功能也照常工作。

### 分片运行 {#sharded-runs}

当你 <.localized_link href="/guides/features/test-sharding/gradle">对测试进行分片</.localized_link> 时，每个开启覆盖率的运行分片都会报告其所运行测试的覆盖率，Tuist 会将一次运行的所有分片合并为一个数据。分片旨在运行套件的一部分，因此不会导致提交的覆盖率不完整。

### 在 CI 上完成每个提交 {#complete-each-commit}

一个提交的覆盖率通常来自多个作业，例如每个分片一个作业。Tuist 无法判断最后一个作业何时上报，因此需要你明确告知。当某个提交的所有测试作业完成后，在一个依赖于所有这些作业的作业中运行以下命令：

```sh
./gradlew tuistCoverageComplete
```

该任务从 `GIT_COMMIT` 或检出目录的 `HEAD` 读取提交信息；传递 `-Ptuist.coverage.commit=<sha>` 可指定其他提交。在提交标记为完成之前，其覆盖率显示为 **进行中**，且不计入分支趋势。

## 工作原理 {#how-it-works}

### Tuist 测量的内容 {#what-tuist-measures}

- **项目。** 每个 Gradle 项目在仪表板上都是一个模块，拥有独立的覆盖率数据。
- **仅产品代码。** 从测试源集编译的类属于测试代码。Tuist 会存储它们，但在所有统计数据中将其排除。
- **你仓库中的文件。** 类归属于其在仓库路径下编译所在的源文件。生成的源代码和被 Git 忽略的文件不会被报告。
- **每行代码是否执行。** JaCoCo 记录代码是否执行，而非执行次数，因此仪表板上的执行计数为 0 或 1。

### 每个测试执行的代码 {#per-test-evidence}

对于在 JUnit Platform 上运行的测试（JUnit 5，或通过 JUnit Vintage 运行的 JUnit 4），插件还会记录每个测试执行的代码，以及每个测试类在测试之外执行的代码（例如在 `@BeforeAll` 中）。这使得 Tuist 能够延续被运行遗漏的测试的覆盖率（参见 [跳过的测试](#skipped-tests)）。无需向测试中添加任何内容。

当每个测试 JVM 一次只运行一个测试时，此功能有效。除非你启用 JUnit 的并行执行，否则 Gradle 默认以这种方式运行测试。使用 `maxParallelForks` 在多个 JVM 中运行测试类是可以的。在同一 JVM 中同时运行的测试仍会计入覆盖率，但无法区分单个测试。

### 构建缓存 {#build-cache}

从构建缓存恢复或已是最新状态的测试任务不会运行任何测试。但其覆盖率仍会被上传：JaCoCo 的数据是任务的输出之一，由在相同输入上执行测试的运行所记录。

### 跳过的测试 {#skipped-tests}

当一次运行遗漏了某些测试时，只要这些测试执行的代码未发生变化，Tuist 就会从之前的运行中补充其覆盖率。如果无法补充，则该提交的覆盖率显示为 **不完整**。运行可能遗漏的情况包括：

- **排除了某个项目的测试任务**，使用 `-x :app:test`。其测试将从代码未变的最近一次运行中延续。
- **部分项目的测试**，使用 `./gradlew :core:test`，或 **部分测试**，使用 `--tests`。该运行仅覆盖你请求的内容，因此除非该提交的其他运行执行了所有测试，否则提交被视为不完整。
- **在首次失败时停止的测试任务**（`failFast`）。

某些测试是故意被遗漏的，不会导致提交不完整：

- **构建脚本中的过滤器**，例如 `filter { excludeTestsMatching(...) }`，它们定义了套件的运行范围。
- **构建脚本禁用的测试任务**，通过 `enabled = false` 或跳过它们的 `onlyIf` 实现。
- **被 <.localized_link href="/guides/features/test-insights/flaky-tests/gradle">隔离</.localized_link> 跳过的测试。** 它们被视为已移除，因此仅由它们覆盖的行计为未覆盖。
- **其他分片的测试**，当你 [对测试进行分片](#sharded-runs) 时。

### 完整和不完整的提交 {#commit-status}

| 状态 | 含义 |
| --- | --- |
| 进行中 | 已有运行上报覆盖率，但 `tuistCoverageComplete` 尚未针对该提交执行。 |
| 完整 | 该提交的所有运行中的测试均已执行、被延续或故意被遗漏。 |
| 不完整 | 部分覆盖率无法确定，因此该数值为下限。 |
| 未测量 | 没有运行上报该提交的覆盖率。 |

分支的趋势仅包含完整的提交。

## 性能影响 {#performance-impact}

JaCoCo 在测试 JVM 加载类时对其进行插桩，因此无论是否启用覆盖率，你编译的类和编译任务的构建缓存条目都保持不变。读取每个依赖配置的任务（例如 SBOM 生成器）也会看到 JaCoCo 代理，因此当你启用覆盖率时，它们的输出会发生变化。测试运行速度会稍慢一些，插件会在测试任务完成后读取 JaCoCo 的数据。启用和禁用覆盖率的测试任务拥有独立的构建缓存条目，因此即使未启用覆盖率的结果已被缓存，首次启用覆盖率的运行仍会执行测试。

## 限制 {#limitations}

- **隔离项目和按需配置。** 这些构建不会配置每个项目，因此插件无法判断运行遗漏了哪些项目的测试，而仅运行部分项目测试的运行会被计为完整。
- **来自分叉仓库的拉取请求不提供覆盖率。** 只有通过与 Tuist 身份验证的运行才会上报覆盖率，而 CI 通常会扣留来自分叉仓库的拉取请求的密钥和身份令牌。

## 查询覆盖率 {#querying}

仪表板的 **代码覆盖率** 页面显示每个提交的数值、其模块及其文件，以及每次运行覆盖的行。智能体可以通过 <.localized_link href="/guides/features/agentic-coding/mcp">模型上下文协议服务器</.localized_link> 访问相同的数据。
