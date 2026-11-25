---
{
  "title": "Gradle 代码覆盖率",
  "titleTemplate": ":title · 代码覆盖率 · 功能 · 指南 · Tuist",
  "description": "上传使用 JaCoCo 测量的 Gradle 项目测试的代码覆盖率，并按文件、项目和提交进行跟踪。"
}
---
# Gradle 代码覆盖率 {#gradle-code-coverage}

代码覆盖率告诉你测试执行了代码中的哪些行。Tuist Gradle 插件使用 JaCoCo 测量测试任务的覆盖率，并在每次测试运行时上传；Tuist 会将一次提交的所有运行合并为一个数值，分别对应整个项目、每个 Gradle 项目以及每个文件。仪表板的**代码覆盖率**页面按提交展示该数值，并显示每个分支的趋势。

> [!IMPORTANT]
> **要求**
>
> - 已应用 `dev.tuist` Gradle 插件，如<.localized_link href="/guides/get-started/gradle-project">开始使用 Gradle 项目</.localized_link>中所述
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

或者通过环境变量为单次调用（例如 CI 任务）开启覆盖率，该方式优先于上述配置：

```sh
TUIST_TEST_COVERAGE=1 ./gradlew test
```

开启和关闭覆盖率的测试任务拥有独立的构建缓存条目（参见[性能影响](#performance-impact)），因此当你的 CI 和本地构建共享构建缓存时，建议使用该配置：仅在 CI 中开启覆盖率可避免它们复用彼此的测试结果。

开启覆盖率后，插件会为每个 JVM 项目应用 Gradle 的 `jacoco` 插件。JaCoCo 代理来自你项目的仓库，就像你自己应用该插件一样。已经配置 JaCoCo 的项目会保留其设置，其原有报告仍可正常工作。

插件仅报告你仓库中代码的覆盖率，因此将 JaCoCo 限制在该范围内：除非测试任务自行设置 JaCoCo 的 `includes`，否则代理只会检测你仓库编译的类所在的包。依赖项、Android 框架以及你的测试框架将在未检测状态下运行，从而保持 JaCoCo 数据和测试任务的构建缓存条目较小。

### Android 项目 {#android-projects}

该插件测量 Android 项目的本地单元测试，例如 `testDebugUnitTest`。在设备或模拟器上运行的检测测试不会被测量。

如果你的单元测试使用 Robolectric，请告诉 JaCoCo 包含 Robolectric 加载的类。Robolectric 在其自己的类加载器中定义应用的类，而 JaCoCo 默认会跳过此类类，导致这些测试执行的代码显示为未覆盖。在 Android 项目的 `build.gradle.kts` 中：

```kotlin
pluginManager.withPlugin("jacoco") {
    tasks.withType<Test>().configureEach {
        extensions.configure<JacocoTaskExtension> {
            isIncludeNoLocationClasses = true
            excludes = listOf("jdk.internal.*")
        }
    }
}
```

该代码块仅在开启覆盖率时生效，因为此时插件才会应用 `jacoco`。

Android 单元测试默认在 JUnit 4 上运行，这会记录覆盖率，但不会记录[每个测试执行的代码](#per-test-evidence)。要记录这些信息，请通过 JUnit Vintage 在 JUnit Platform 上运行它们。

### 分片运行 {#sharded-runs}

当你<.localized_link href="/guides/features/test-sharding/gradle">对测试进行分片</.localized_link>时，每个开启覆盖率的分片都会报告其执行的测试覆盖率，Tuist 会将一次运行的各个分片合并为一个数值。分片有意只运行套件的一部分，因此不会导致提交的覆盖率不完整。

### 在 CI 上完成每次提交 {#complete-each-commit}

一次提交的覆盖率通常来自多个任务，例如每个分片一个任务。Tuist 无法判断最后一个任务何时完成报告，因此需要你告知它。当一次提交的所有测试任务完成后，在一个依赖于所有这些任务的任务中运行以下命令：

```sh
./gradlew tuistCoverageComplete
```

当单个任务运行某次提交的所有测试时，请将该任务作为测试后的步骤运行，包括测试失败的情况：即使测试失败，运行仍会报告其覆盖率。

该任务从检出的 `HEAD` 读取提交，即你的测试所运行的提交；传递 `-Ptuist.coverage.commit=<sha>` 以指定其他提交。在提交完成之前，其覆盖率显示为**进行中**，且不会纳入其分支的趋势中。

## 工作原理 {#how-it-works}

### Tuist 测量的内容 {#what-tuist-measures}

- **项目。** 每个 Gradle 项目在仪表板上都是一个模块，拥有各自的覆盖率。
- **仅限产品代码。** 从测试源集编译的类属于测试代码。Tuist 会存储它们，但不会将其计入任何数值。
- **你仓库中的文件。** 类按其编译来源的源文件计数，路径基于其在仓库中的位置。生成的源文件和 Git 忽略的文件不会被报告。
- **每行代码是否执行。** JaCoCo 记录代码是否执行，而非执行次数，因此仪表板上的执行计数为 0 或 1。

### 每个测试执行的代码 {#per-test-evidence}

对于在 JUnit Platform 上运行的测试（JUnit 5，或通过 JUnit Vintage 运行的 JUnit 4），插件还会记录每个测试执行的代码，以及每个测试类在测试之外执行的代码，例如在 `@BeforeAll` 中。这使得 Tuist 能够延续被运行遗漏的测试的覆盖率（参见[跳过的测试](#skipped-tests)）。无需向你的测试中添加任何内容。

这在每个测试 JVM 一次运行一个测试时有效，除非你启用 JUnit 的并行执行，否则 Gradle 就是这样运行测试的。使用 `maxParallelForks` 在多个 JVM 中运行测试类是可以的。在同一 JVM 中同时运行的测试仍会计入覆盖率，但不会逐个区分。

### 构建缓存 {#build-cache}

从构建缓存恢复或已是最新状态的测试任务不会运行任何测试。其覆盖率仍会被上传：JaCoCo 数据是任务的输出之一，由在相同输入上执行其测试的运行记录。

### 跳过的测试 {#skipped-tests}

当一次运行遗漏某些测试时，只要它们执行的代码未发生变化，Tuist 就会从之前的运行中填充其覆盖范围。如果无法做到，提交的覆盖率将标记为**不完整**。运行遗漏的内容包括：

- **排除项目的测试任务**，使用 `-x :app:test`。其测试将从代码未变化的最近一次运行中延续。
- **部分项目的测试**，使用 `./gradlew :core:test`；或**部分测试**，使用 `--tests`。该运行仅覆盖你请求的内容，因此除非该提交的另一次运行执行了所有内容，否则提交将不完整。
- **在首次失败时停止的测试任务**（`failFast`）。

有些测试是有意遗漏的，不会导致提交不完整：

- **构建脚本中的过滤器**，例如 `filter { excludeTestsMatching(...) }`，用于定义套件运行的内容。
- **构建脚本禁用的测试任务**，通过 `enabled = false` 或跳过它们的 `onlyIf` 实现。
- **被<.localized_link href="/guides/features/test-insights/flaky-tests/gradle">隔离</.localized_link>跳过的测试。** 它们被视为已移除，因此仅由它们覆盖的行将计为未覆盖。
- 当你[分片运行测试](#sharded-runs)时，**其他分片的测试**。

### 完整和不完整的提交 {#commit-status}

| 状态 | 含义 |
| --- | --- |
| 进行中 | 已有运行报告了覆盖率，但该提交尚未运行 `tuistCoverageComplete`。 |
| 完整 | 该提交的所有运行中的每个测试均已执行、延续或被有意遗漏。 |
| 不完整 | 部分覆盖率无法确定，因此该数值为下限。 |
| 未测量 | 没有运行报告该提交的覆盖率。 |

分支的趋势仅包含完整的提交。

## 性能影响 {#performance-impact}

JaCoCo 在测试 JVM 加载类时对其进行插桩，因此无论是否启用覆盖率，编译后的类和编译任务的构建缓存条目都保持不变。读取每个依赖配置的任务（如 SBOM 生成器）也会看到 JaCoCo 代理，因此启用覆盖率后其输出会发生变化。测试运行速度稍慢，插件会在测试任务完成后读取 JaCoCo 数据。启用和禁用覆盖率的测试任务拥有独立的构建缓存条目，因此即使未启用覆盖率的结果已被缓存，首次启用覆盖率的运行仍会执行测试。

## 限制 {#limitations}

- **隔离项目和按需配置。** 这些构建不会配置每个项目，因此插件无法判断运行遗漏了哪些项目的测试，而运行部分项目的测试将被计为完整。
- **来自 fork 的拉取请求不提供覆盖率。** 覆盖率仅由通过 Tuist 身份验证的运行上传，而 CI 通常会扣留来自 fork 的拉取请求的秘密信息和身份令牌。

## 查询覆盖率 {#querying}

仪表板的**代码覆盖率**页面显示每个提交的数值、其模块和文件，以及每次运行覆盖的行。代理可以通过<.localized_link href="/guides/features/agentic-coding/mcp">模型上下文协议服务器</.localized_link>访问相同的数据。
