---
{
  "title": "Module cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Cache compiled binaries and share them across your team with Tuist Module Cache."
}
---

# 模块缓存 {#module-cache}

> [!WARNING]
> **要求**
>
> - 一个<.localized_link href="/guides/features/projects">生成的项目</.localized_link>。模块缓存会读取 Tuist 在 `Project.swift` 背后维护的项目图，以对目标进行哈希处理并替换其二进制文件。

Tuist 模块缓存提供了一种强大的方式来优化构建时间，通过将模块缓存为二进制文件（`.xcframework`s）并在不同环境中共享它们。此功能允许你利用之前生成的二进制文件，减少重复编译的需要并加快开发过程。

> [!TIP]
> **与 Xcode 缓存结合使用**
>
> 模块缓存和<.localized_link href="/guides/features/cache/xcode-cache">Xcode 缓存</.localized_link>是互补的，因为它们在不同的粒度级别上工作。模块缓存在构建运行之前用预构建的 `.xcframework`s 替换整个模块，而 Xcode 缓存在构建期间重用编译输出。
>
> 编译缓存设置不是模块缓存哈希的一部分，因此开启或关闭 Xcode 缓存会保留你已经预热的二进制文件。在 Xcode 27 及更高版本中，随附的前缀映射设置会被哈希化。请参阅<.localized_link href="/guides/features/cache/xcode-cache#module-cache-hashes">模块缓存哈希</.localized_link>。

## 预热 {#warming}

Tuist 高效地<.localized_link href="/guides/features/projects/hashing">利用哈希</.localized_link>来检测依赖图中每个目标的更改。利用这些数据，它构建并为源自这些目标的二进制文件分配唯一标识符。在生成图时，Tuist 随后无缝地将原始目标替换为其对应的二进制版本。

此操作称为 *“预热”*，它会生成用于本地使用或通过 Tuist 与团队成员和 CI 环境共享的二进制文件。预热缓存的过程很简单，可以通过一个简单的命令启动：

```bash
tuist cache
```

该命令重用二进制文件以加快进程。

如果某个二进制文件上传失败，该命令仍会上传其余文件，然后以非零状态退出并列出未上传的目标。机器本地缓存中的二进制文件被视为已缓存，因此要从同一台机器再次上传它们，请在预热之前运行 `tuist clean binaries`。传递 `--no-upload` 以仅将二进制文件存储在本地缓存中。

### 目标选择 {#destination-selection}

使用 `--destination simulator` 或 `--destination device` 为一个目标进行缓存和生成：

```bash
tuist cache --destination simulator
tuist generate --destination simulator

tuist cache --destination device
tuist generate --destination device
```

默认值是 `all`，它会保留你的目标支持的每个目标平台，包括 Mac Catalyst。后续的 `tuist cache` 会重用缓存的切片并仅构建缺少的 SDK。常规生成会在缺少任何所需切片时保留模块的源代码。

受限生成将源目标限制为所选目标平台，并保留原生 macOS 目标，包括宏。两种受限模式都不包括 Mac Catalyst。使用 `--destination all` 重新生成以恢复所有目标平台。

逐切片缓存支持具有标准架构的 iOS 和 macOS。其他平台、自定义架构和不支持的产品保留完整构件缓存。遗留模块缓存需要 `--destination all`。

### 远程上传准入 {#remote-upload-admission}

现代模块缓存使用 REAPI。当繁忙的缓存暂时以 `RESOURCE_EXHAUSTED` 拒绝上传时，Tuist 会以抖动方式退避，遵守标准的 `google.rpc.RetryInfo` 最小延迟，并在有限的等待预算内重试。每次调用最多允许六次重试上传准入。每个 blob 上传操作在其存在性检查、批量上传和流式写入之间共享一个 60 秒的累计退避预算；并发等待各自消耗预算，因此多次拒绝不会让每个排队的 blob 再获得一分钟的重试时间。成功的传输不消耗此预算，并且在预算耗尽时不会被取消。动作结果发布有其自己的有限预算。指数延迟从一秒开始，在比例抖动之前增长到 30 秒。如果服务器要求的延迟超过剩余预算，Tuist 会失败而不是早于指示进行重试。取消会中断退避，并且缓存读取保留短重试，以便过载不会停滞生成。

这些默认值也有助于没有重试提示的旧版 Kura 版本。更长的重试吸收临时争用，而非持续过载：如果拒绝持续存在，请减少热作业上的[缓存并发限制](#cache-concurrency-limit)或增加服务器容量。请参阅[Kura 上传大小调整](https://github.com/tuist/tuist/blob/main/kura/README.md#upload-admission-and-sizing)以获取 pod 内存估算和准入指标。

### 配置选择 {#configuration-selection}

在不传递 `--configuration` 的情况下预热缓存时，Tuist 按以下顺序选择要使用的构建配置：

1. 清单的 `Project.Options.generationOptions` 中设置的 [`defaultConfiguration`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist/generationoptions/defaultconfiguration)（如果有）。
2. 否则，变体 `debug` 的第一个构建配置，按名称字母顺序排序。

要为特定配置预热缓存，请显式传递它：

```bash
tuist cache --configuration Release
```

## 用法 {#usage}

默认情况下，当 Tuist 命令需要生成项目时，如果可用，它们会自动用缓存中的二进制等效项替换依赖项。此外，如果你指定要关注的目标列表，Tuist 还将用其缓存的二进制文件替换任何依赖目标，前提是它们可用。对于那些喜欢不同方法的人，可以选择使用特定标志完全退出此行为：

::: code-group
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --cache-profile none # No cache at all
```

```bash [Testing]
tuist test
```
<!-- -->
:::

> [!WARNING]
> 二进制缓存是一项专为开发工作流程设计的功能，例如在模拟器或设备上运行应用程序，或运行测试。它不适用于发布构建。在归档应用程序时，通过使用 `--cache-profile none` 生成包含源代码的项目。

## 缓存配置文件 {#cache-profiles}

Tuist 支持缓存配置文件，以控制在生成项目时用缓存的二进制文件替换目标的积极程度。

- 内置：
  - `only-external`：仅替换外部依赖项（系统默认）
  - `all-possible`：尽可能多地替换目标（包括内部目标）
  - `none`：从不使用缓存的二进制文件替换

在 `tuist generate` 上使用 `--cache-profile` 选择配置文件：

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely
tuist generate --cache-profile none
```

> [!NOTE]
> **已弃用的标志**
>
> `--no-binary-cache` 标志已弃用。请改用 `--cache-profile none`。出于向后兼容性考虑，已弃用的标志仍然有效。

解析有效行为时的优先级（从高到低）：

1. `--cache-profile none`
2. 目标焦点（将目标传递给 `generate`）→ 配置文件 `all-possible`
3. `--cache-profile <value>`
4. 配置默认值（如果已设置）
5. 系统默认值 (`only-external`)

## 支持的产品 {#supported-products}

只有以下目标产品可由 Tuist 缓存：

- 框架（静态和动态），包括依赖于 [XCTest](https://developer.apple.com/documentation/xctest) 或 Swift Testing 的测试支持框架
- 库（静态和动态），包括依赖于 XCTest 或 Swift Testing 的测试支持库
- Bundle
- Swift 宏

测试 Bundle 仍被排除在模块缓存之外。这意味着 `unitTests` 和 `uiTests` 目标不会作为二进制文件缓存，但测试所依赖的常规框架和库目标即使链接了 XCTest 或 Swift Testing 也可以缓存。

缓存的库 `.xcframework` 保留了生成的项目导入它们所需的元数据，包括 Swift 模块以及当源目标声明公共头文件时的公共 C/Objective-C 头文件。

> [!NOTE]
> **上游依赖项**
>
> 当一个目标不可缓存时，它也会使上游目标不可缓存。例如，如果你有依赖图 `A > B`，其中 A 依赖于 B，如果 B 不可缓存，A 也将不可缓存。

## 分析 {#analytics}

在项目的仪表板中打开 **模块缓存 → 模块** 以查找频繁未命中的模块。选择你想要改进的环境，例如 **CI**，以及日期范围。概览显示缓存命中、未命中以及未命中的模块；打开一个模块会显示其历史记录以及为每次观察分配的原因。

**未命中** 下拉菜单选择一个原因的数量和解释。图表显示所有四个原因的分布。在模块页面上，使用历史记录的 **原因** 过滤器检查个别出现情况。将鼠标悬停在原因徽章上，或使用键盘聚焦它，以查看其定义。

### 未命中原因 {#miss-reasons}

| 原因 | 含义 |
| --- | --- |
| **已更改** | 模块自身的比较输入已更改。这些包括文件哈希、构建设置、解析的配置和编译器标识符。源代码编辑只是可能的原因之一。 |
| **上游** | 模块自身的比较输入保持不变，但其依赖项或外部包的哈希已更改。模块的源文件可以保持不变。 |
| **冷启动** | 没有早期的模块观察可供比较，或者报告的输入无法解释未命中，并且没有符合条件的早期远程可用性证据。冷启动并不证明该模块从未被缓存。 |
| **已驱逐** | 确切的缓存密钥以前在同一项目的同一记录的缓存端点上有远程命中，但现在未命中。 |

对于标记为 **已驱逐** 的未命中，工件之前已从远程缓存下载，但这次无法重用。驱逐是可能的原因，尽管访问或下载失败也可以解释未命中。Tuist 仅在找到早期的远程命中时才分配此标签；之前的未命中和本地命中是不够的。

例如：

| 场景 | 分类 |
| --- | --- |
| 模块未命中，没有早期观察或符合条件的远程命中 | 冷启动 |
| A 更改；B 依赖于 A，C 依赖于 B；所有三个密钥都更改 | A 是已更改；B 和 C 是上游 |
| 预热后编译器版本更改，源代码和设置不变 | 当两次观察都报告编译器输入时，受影响的未命中为已更改 |
| 确切的密钥已从远程下载，然后在其工件被驱逐后未命中 | 已驱逐，当早期命中符合证据条件时 |
| 密钥反复未命中且从未成功预热 | 它可以保持冷启动 |

原因描述的是观察结果；它们不是附加在密钥上的永久标签。例如，编译器升级后的第一次未命中可能是“已更改”，而如果该新密钥从未被观察到远程可用，则随后的未命中可能是“冷启动”。

### 提高缓存命中率 {#improving-cache-hit-rate}

1. **选择一致的基线。** 从 CI 和具有代表性的日期范围开始。按未命中次数对模块进行排序，然后考虑其命中率、依赖项和构建成本。修复经常未命中的昂贵依赖项比提高微小模块的命中率更能节省时间。在进行更改后，比较相同的环境和类似的工作负载。
2. **调查“已更改”未命中。** 打开相关的运行记录并比较其完整密钥和报告的输入。将预热和使用作业与预期的 Xcode/编译器版本、配置和目标目的地对齐。在有意更改后再次预热。如果易变的生成文件或依赖于环境的设置使原本稳定的模块失效，请调查这些输入。将影响二进制兼容性的输入保留在哈希中。
3. **追踪“上游”未命中到已更改的依赖项。** 检查其历史记录以找到直接更改。预热生成的密钥可以恢复重用。如果频繁更改的实现使许多昂贵的依赖项失效，请考虑使用更小的模块或稳定的接口，如 [效率](#efficiency) 中所述。
4. **检查“冷启动”未命中的预热覆盖范围。** 验证预热是否选择了所需的模块，使用了消费作业的配置和环境，并成功上传了工件。检查实际 CI 作业使用的完整密钥。如果预热和消费请求不同的密钥，请在假设缓存被驱逐之前检查哈希输入。即使模块的源代码没有更改，也可能出现反复未命中且之前没有成功上传的情况。
5. **利用“已驱逐”未命中的证据。** 确认消费运行的密钥和端点，然后检查消费运行的缓存警告和预热作业的上传结果。在适用时检查保留或驱逐情况。重新预热所需的工件并验证后续命中。如果仍然未命中，请与支持团队分享相关的运行链接和日志。

要进行哈希比较，请在每个相关环境中运行此命令，使用你打算预热和消费的 configuration：

```bash
tuist hash cache --configuration Debug --verbose
```

比较模块的完整哈希和组件块。在同一台未更改的机器上重复执行命令通常应产生相同的结果；比较实际的预热和消费环境以调查不匹配之处。这两个命令都不需要命中缓存。请参阅 <.localized_link href="/guides/features/projects/hashing#debugging">哈希诊断</.localized_link> 以进行进一步检查。

## 效率 {#efficiency}

通过二进制缓存可以达到的效率水平在很大程度上取决于图结构。为了获得最佳结果，我们建议如下：

1. 避免非常嵌套的依赖图。图越浅越好。
2. 使用协议/接口目标而不是实现目标来定义依赖关系，并从最顶层的目标依赖注入实现。
3. 将频繁修改的目标拆分为更小的目标，以降低其更改的可能性。

上述建议是 <.localized_link href="/guides/features/projects/tma-architecture">模块化架构</.localized_link> 的一部分，我们提议将其作为构建项目结构的一种方式，以最大化二进制缓存以及 Xcode 功能的好处。

## 推荐设置 {#recommended-setup}

我们建议设置一个 CI 作业，**在主分支的每次提交中运行** 以预热缓存。这将确保缓存始终包含 `main` 中更改的二进制文件，以便本地和 CI 分支在其基础上进行增量构建。

> [!TIP]
> **保持缓存预热隔离**
>
> 在专用的 CI 步骤中运行 `tuist cache`，不要有依赖于生成的工作区的后续步骤。由于 `tuist cache` 会出于缓存构建目的修改工作区，因此任何需要工作区的 CI 步骤都应首先运行 `tuist generate` 以获得一个新的、可用的工作区。

> [!TIP]
> **缓存预热使用二进制文件**
>
> `tuist cache` 命令还利用二进制缓存来加速预热。

以下是一些常见工作流的示例：

### 开发人员开始处理新功能 {#a-developer-starts-to-work-on-a-new-feature}

1. 他们从 `main` 创建一个新分支。
2. 他们运行 `tuist generate`。
3. Tuist 从 `main` 拉取最新的二进制文件并用它们生成项目。

### 开发人员向上游推送更改 {#a-developer-pushes-changes-upstream}

1. CI 管道将运行 `xcodebuild build` 或 `tuist test` 来构建或测试项目。
2. 工作流将从 `main` 拉取最新的二进制文件并用它们生成项目。
3. 然后它将增量构建或测试项目。

## 配置 {#configuration}

### 缓存并发限制 {#cache-concurrency-limit}

将 `TUIST_CACHE_CONCURRENCY_LIMIT` 设置为正整数以限制下载和上传。例如，减少预热作业中小型自托管缓存的负载：

```bash
TUIST_CACHE_CONCURRENCY_LIMIT=2 tuist cache
```

当未设置时，REAPI 上传使用八个传输任务。当任何 blob 需要 ByteStream 时，下载使用八个，而对于仅批量计划则使用 32 个。传统 HTTP 缓存路径默认为 100；该默认值不适用于 REAPI。无效值（包括之前记录的 `none`）将保留默认值而不是移除限制。使用 `unset TUIST_CACHE_CONCURRENCY_LIMIT` 恢复默认值。

限制适用于每次传输操作，而不是全局应用于所有操作或 CI 作业。三个同时进行的预热作业，限制为两个，可能对同一缓存有六个活跃的上传。消费者作业可以将变量保持未设置状态，以保留默认的下载并行性。

### 缓存预热临时目录 {#cache-warm-scratch-directory}

默认情况下，`tuist cache` 会为构建中间件和组装的缓存工件创建一个临时暂存目录，然后在缓存预热完成后将其删除。要将这些文件保留在你管理的目录下，请设置 `TUIST_CACHE_WARM_SCRATCH_DIRECTORY`。

路径可以是绝对路径或相对于当前工作目录的路径。当目录不存在时，Tuist 会创建它。如果它已经存在，它必须是一个空目录。

设置此环境变量后，Tuist 会在命令完成后保留目录及其内容。调用者负责在下一次缓存预热之前清理它。当变量未设置时，Tuist 会继续使用并删除临时目录。

当需要预热外部构建目标时，Tuist 会拒绝调用者拥有的暂存目录。外部构建脚本控制其自身的输出位置，因此 Tuist 无法保证这些输出保留在暂存目录内。

### 代码覆盖率 {#code-coverage}

> [!NOTE] EARLY ACCESS
> 模块缓存的代码覆盖率处于早期访问阶段。仅当设置了 `TUIST_FEATURE_FLAG_COVERAGE=1` 时，命令才会读取和预热下面描述的插桩二进制文件。

来自模块缓存的目标是一个预构建的二进制文件，只有在该二进制文件是使用覆盖率计数器构建的情况下，测试运行才会测量其代码。在 `Tuist.swift` 中为你的项目开启覆盖率：

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            coverage: .coverage(enabled: true)
        )
    )
)
```

使用 `enabled` 时，每个命令和每个环境都会为你项目的自有目标读取一个插桩版本的缓存，因此在 CI 上的一次预热即可服务于 CI 和本地机器：

| 命令 | 你项目的目标 | 外部包 |
| --- | --- | --- |
| `tuist cache`（Debug 配置） | 预热插桩二进制文件 | 预热普通二进制文件 |
| `tuist cache`（Release 配置） | 预热普通二进制文件 | 预热普通二进制文件 |
| `tuist hash cache` | 打印插桩键 | 打印普通键 |
| `tuist generate` | 读取插桩二进制文件 | 读取普通二进制文件 |
| `tuist test` | 读取插桩二进制文件 | 读取普通二进制文件 |

该选项适用于 Xcode 视为 Debug 的每种配置。Release 构建从不进行插桩。Tuist 还会在这些配置中链接剖析运行时（`CLANG_COVERAGE_MAPPING_LINKER_ARGS`），因此不收集覆盖率的构建仍然会链接插桩二进制文件，并在它自动生成的方案以及你定义的将 `coverage` 留空的方案的测试操作中开启覆盖率。

你定义的方案遵循该选项，除非它自行设置覆盖率：`.options(coverage: false)` 保持关闭，而 `.options(coverage: true)` 保持开启，无论选项如何规定。测试计划自行决定覆盖率，并且 `-enableCodeCoverage` 仍然像在 Xcode 中一样覆盖单次运行。读取插桩二进制文件但不收集覆盖率的运行会正常构建和测试。当运行收集覆盖率但你项目的目标作为普通二进制文件来自缓存时，Tuist 会警告未测量它们的覆盖率。

`TUIST_COVERAGE_ENABLED` 环境变量（`1` 或 `0`）优先于 `coverage: .coverage(enabled:)`。为整个环境（例如 CI 工作流）而不是单个命令设置它，以便预热缓存的命令和读取缓存的命令保持一致。

`prefixMapping`（参见 <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">Xcode 缓存</.localized_link>）有其自己的覆盖设置：`TUIST_COVERAGE_PREFIX_MAPPING` 环境变量（`1` 或 `0`）优先于 `coverage: .coverage(prefixMapping:)`。

覆盖为关闭会读取普通变体，而开启覆盖率预热的缓存不会填充该变体，因此这些目标将从源代码构建。Release 预热始终预热普通二进制文件。

> [!IMPORTANT] KEEP THE VALUES THE SAME EVERYWHERE
> `enabled` 和 `prefixMapping` 会更改你项目目标的构建设置和缓存键，以及其测试目标的选择性测试哈希值。在共享缓存的每台机器上将它们设置为相同的值，不要从环境中派生它们（例如从 `Environment.isCI`）：CI 和本地机器之间的值不同会导致它们拥有不同的键。环境变量也是如此：使用 `TUIST_COVERAGE_ENABLED=0` 的运行不会重用开启覆盖率的运行的二进制文件或选择性测试结果。

请记住：

- 插桩二进制文件更大：静态归档和动态库大约增加 20–30%。Debug 构建以相同的速度运行。
- 无论是否使用此选项，Xcode 的覆盖率报告从不显示来自缓存的代码。Tuist 的覆盖率上传会测量它。要在 Xcode 中查看目标的覆盖率，请使用 `tuist generate <target>` 聚焦它，以便从源代码构建。

## 故障排除 {#troubleshooting}

### 它不为我的目标使用二进制文件 {#it-doesnt-use-binaries-for-my-targets}

确保 <.localized_link href="/guides/features/projects/hashing#debugging">哈希是确定性的</.localized_link> 跨环境和运行。如果项目引用了环境（例如通过绝对路径），可能会发生这种情况。你可以使用 `diff` 命令来比较由两次连续调用 `tuist generate` 生成的项目，或者跨环境或运行进行比较。

还要确保目标不直接或间接依赖于 <.localized_link href="/guides/features/cache/module-cache#supported-products">不可缓存的目标</.localized_link>。

### 缺少符号 {#missing-symbols}

使用源代码时，Xcode 的构建系统通过 Derived Data 可以解析未显式声明的依赖项。但是，当你依赖二进制缓存时，必须显式声明依赖项；否则，当找不到符号时，你很可能会看到编译错误。为了调试此问题，我们建议使用 <.localized_link href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect dependencies --only implicit`</.localized_link> 命令，并在 CI 中设置它以防止隐式链接回归。
