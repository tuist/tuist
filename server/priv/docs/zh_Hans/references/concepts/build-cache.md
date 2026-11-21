---
{
  "title": "什么是构建缓存？详解本地与远程构建缓存",
  "titleTemplate": ":title · Tuist",
  "description": "构建缓存会复用先前构建的输出。介绍 Xcode、Gradle 和 Bazel 中本地与远程构建缓存的工作原理，Xcode 缓存的含义，以及何时使用缓存能带来收益。"
}
---
# 什么是构建缓存？ {#what-is-a-build-cache}

构建缓存将各个构建步骤的输出（例如编译后的目标文件、模块、库或测试结果）存储在根据生成这些输出所需的所有内容计算得出的键下：源文件、编译器标志、依赖项、环境和工具链版本。当后续构建需要某个输入产生相同键的步骤时，构建系统会直接使用存储的输出，而不是再次运行该步骤。**本地构建缓存**存在于单台机器上，并加速该机器的后续构建。**远程构建缓存**是一个共享服务器，许多机器可以从中读取和写入，因此 CI 作业、团队成员或编码代理可以重用其他人已经构建好的输出。

## 构建缓存、增量构建和 CI 缓存 {#build-cache-incremental-build-and-ci-cache}

有三种概念常被称为“缓存”，但它们的行为各不相同：

- **增量构建**重用已存在于你本地构建目录中的输出，仅重新构建自上次构建以来发生变化的部分。它们通常依赖于文件时间戳或与构建产物一起保存的依赖关系图。切换分支、移动检出目录或在全新机器上开始工作时，都会丢失这种状态。
- **构建缓存**根据输入的内容来查找输出，而不是根据同一目录中最近构建的内容。这使得只要输入匹配，输出就可以跨分支、检出目录和机器重用。
- **CI 目录缓存**（例如 GitHub Actions 上的 `actions/cache`）会在作业结束时保存一个目录，并在下一个作业开始时使用你选择的键（例如锁文件哈希）恢复它。这是一种文件传输，而非构建缓存：构建系统仍然决定要重新构建什么，而恢复的目录可能部分或完全过时。

依赖缓存（例如下载的包或 Gradle 或 Swift 包缓存）则不同：它们节省的是网络获取过程，而非编译过程。

## 构建缓存的工作原理 {#how-a-build-cache-works}

支持缓存的构建系统将构建拆分为多个步骤（Bazel 称其为 action，Gradle 称其为 task），并对每个步骤执行相同的操作：

1. **计算缓存键。** 构建系统对可能影响输出的每个输入进行哈希处理：输入文件的内容、命令行或任务配置、相关的环境变量以及工具链。
2. **查找键。** 它首先检查本地缓存，如果配置了远程缓存，则接着检查远程缓存。
3. **命中或未命中。** 如果命中，它会下载或复制存储的输出并跳过该步骤。如果未命中，它会运行该步骤，并在允许的情况下将该键下的输出上传。

大多数缓存将输出存储在**内容寻址存储**（CAS）中，其中每个数据块都以其自身内容的哈希值存储，另外还有一个从缓存键到其产生的输出的独立索引。相同的文件只存储一次，客户端可以验证其下载的内容。

该模型有一个严格要求：键必须包含改变输出的每一个输入。如果一个步骤读取了构建系统不知道的输入，例如未声明的文件、环境变量、当前时间或机器上安装的工具，缓存可能会返回与当前输入不匹配的输出。构建系统将仅依赖于声明输入的步骤称为**密封的**。相反的问题更常见且危险性较小：包含无关内容（例如绝对路径或时间戳）的键会在每台机器上产生不同的键，导致缓存永远无法命中。

## 各构建系统的构建缓存工作方式 {#how-it-works-per-build-system}

### Gradle 构建缓存 {#gradle}

[Gradle 构建缓存](https://docs.gradle.org/current/userguide/build_cache.html)存储可缓存任务的输出，例如 Java 和 Kotlin 编译以及测试执行，其键由任务类型、实现、输入属性和规范化输入文件决定。默认情况下它是关闭的。在 `gradle.properties` 中使用 `org.gradle.caching=true` 启用它，或者为单次构建使用 `--build-cache`。

- **本地。** 内置的本地缓存是 Gradle 用户主目录中的一个目录（默认为 `~/.gradle`）。一旦启用构建缓存，它就会生效，并且 Gradle 会定期删除最近未使用的条目。
- **远程。** 远程缓存在 `settings.gradle(.kts)` 中配置，例如使用 `HttpBuildCache`。当本地未命中时，Gradle 会从远程缓存下载输出并本地存储以备下次使用。默认情况下，远程缓存不接受上传；常见的设置是让 CI 推送（在 CI 中运行时 `isPush = true`），而开发者机器只读取。

Gradle 将从缓存恢复的任务报告为 `FROM-CACHE`，这与 `UP-TO-DATE` 不同：up-to-date 表示 Gradle 的增量构建发现任务的输出已经就位，无需查询缓存。配置缓存是第三个独立的功能，它缓存配置阶段的结果，而不是任务输出。

### Bazel 远程缓存 {#bazel}

Bazel 缓存每个 action。它的 action 缓存将 action 的键（命令行、环境和输入文件的摘要）映射到 action 的输出，而输出本身存储在内容寻址存储中。

- **本地。** Bazel 将其 action 缓存和构建输出保留在其输出基础目录中，这使你能够在单个工作区中进行快速的增量构建。`--disk_cache=<path>` 添加了一个磁盘缓存，可在同一台机器上的工作区和分支之间共享。
- **远程。**`--remote_cache=grpcs://…`（或 `https://…`）将 Bazel 指向实现 [Remote Execution API](https://github.com/bazelbuild/remote-apis) 或普通 HTTP 缓存的远程缓存。`--remote_upload_local_results=false` 使机器变为只读，这是许多团队防止开发者机器写入共享缓存的方式。`--remote_download_minimal` 或 `--remote_download_toplevel`（“无字节构建”）避免下载本地构建从不需要的中间输出。

Bazel 还缓存测试结果：输入未发生变化的测试会被报告为 `(cached) PASSED` 而无需运行。远程缓存不同于远程执行，后者还在远程机器上运行 action；缓存仅存储结果。

### 什么是 Xcode 缓存？ {#xcode}

Xcode 使用几种容易混淆的缓存和目录。影响构建时间的包括：

- **DerivedData**（`~/Library/Developer/Xcode/DerivedData/<Project>-<hash>/`）存储每个项目的构建产物、中间文件、索引、日志和已解析的 Swift 包。它是增量构建重用的状态。删除它是安全的，但该项目的下一次构建将变为完全重建，且索引和包解析会再次运行。
- **Clang 模块缓存**（`~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex/`）存储用于导入的 C 和 Objective-C 模块及 SDK 框架的预编译 Clang 模块（`.pcm` 文件），并在项目间共享。启用显式构建模块后，Xcode 会将模块作为常规构建任务进行构建，并将其保留在每个项目的中间文件中。删除它是安全的；模块会按需重新构建。
- **编译缓存**（Xcode 26 及更高版本，默认位于 DerivedData 内的 `CompilationCache.noindex`，可通过 `COMPILATION_CACHE_CAS_PATH` 配置）在 `COMPILATION_CACHE_ENABLE_CACHING = YES` 时存储 Swift、C 和 Objective-C 的内容寻址编译输出。删除它是安全的；本可重放的编译将再次运行。
- **Swift Package Manager 缓存**（`~/Library/Caches/org.swift.swiftpm/`）存储跨项目共享的已下载包仓库和清单。删除它是安全的；包会再次获取。

`~/Library/Developer` 下的其他大型目录并非构建缓存，但在清理磁盘空间时经常出现：`Xcode/Archives` 存储归档的应用构建及其调试符号（保留你可能需要用于符号化崩溃的那些），`Xcode/iOS DeviceSupport` 存储连接设备的操作系统版本的符号，而 `CoreSimulator/Devices` 存储模拟器及其数据（`xcrun simctl delete unavailable` 会移除不再安装的运行时的模拟器）。

DerivedData 是 Xcode 的增量构建状态，而非内容寻址缓存：它与项目在磁盘上的位置以及文件时间戳绑定。从不同路径的 CI 缓存恢复 DerivedData，或者在全新检出更改了每个文件的修改时间后，通常仍会导致完全重建。

**编译缓存** 在 Xcode 26 中引入，是本页意义上的 Xcode 构建缓存。它根据输入内容存储编译结果，并在命中时重放，因此输出能在分支切换和清理构建产物后保留。它缓存的是编译，而非每个构建步骤：链接、资源处理和脚本阶段仍会运行。默认情况下，存储位于单台机器本地并驻留在 DerivedData 内，因此删除整个 DerivedData 会将其丢弃；仅删除项目的构建产物则会保留它。Xcode 还可以通过插件将编译缓存连接到远程缓存服务（`COMPILATION_CACHE_ENABLE_PLUGIN` 和 `COMPILATION_CACHE_REMOTE_SERVICE_PATH`），从而将其转变为共享远程缓存。

在编译缓存出现之前，Xcode 项目主要通过 **二进制缓存** 整个模块来跨机器重用工作：将依赖项构建为预构建框架或 XCFrameworks 并链接它们，而不是编译源代码。这种方式以模块而非编译为粒度运作，并改变了项目的构建方式。

## 延迟、blob 大小和 blob 数量 {#latency-blob-size-and-blob-count}

远程缓存命中并非免费。获取输出会产生固定延迟，因为每个请求都必须等待前一个请求完成，再加上传输其字节所需的时间：

**time ≈ R × L + S / B**

其中 *R* 是无法重叠的往返次数，*L* 是到缓存的往返延迟，*S* 是传输的字节数，*B* 是带宽。哪一项占主导地位取决于构建系统如何将工作切分为 blob：

- **少量大 blob 受带宽限制。** 存储粗粒度输出（例如 Gradle 任务的打包输出或二进制模块缓存中的预构建框架）的缓存发出的请求较少，但每个请求传输兆字节数据。200 MB 的输出集在 100 Mbit/s 下耗时约 16 秒，在 1 Gbit/s 下不到 2 秒，而几毫秒的额外延迟几乎无关紧要。
- **大量小 blob 受延迟限制。** 细粒度缓存（例如 Bazel 的每 action 缓存和 Xcode 的编译缓存）会发出数千次请求来获取几 KB 的 blob，其中许多仅用于查询键是否存在。在 2,000 次查找、同时并发 8 次、延迟为 40 ms 的情况下，构建仅因往返就要等待约 10 秒，无论 blob 有多小。若延迟为 2 ms，同样的查找仅需约半秒。增加带宽对此无益；更近的缓存才有用。
- **未命中也会产生往返开销。** 每次未命中的查找都会增加延迟，却不会节省任何工作。命中率低的远程缓存可能使构建比完全没有远程缓存时更慢。
- **体量会放大两者影响。** blob 的数量随项目结构增长：由许多小模块或目标组成的图比少数大模块产生更多、更小的输出。拆分项目可提高并行性和失效效率，但也使构建对缓存延迟更敏感。

只有当获取输出比重算更快时，命中才值得，而这一比较随距离变化。本地耗时 50 ms 的编译，从同一网络的缓存命中效果良好，但从另一大陆的缓存命中效果较差。这就是为什么远程缓存的优化杠杆主要在于延迟和请求数量，而非原始带宽：

- **将缓存放置在靠近构建运行的位置**，与 CI 运行器处于同一区域或网络，并尽可能靠近开发者。
- **重叠请求。** Bazel 的 Remote Execution API 批量处理存在性检查（`FindMissingBlobs`）和小读取，且 `--remote_max_connections` 限制并发。Xcode 的 `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES` 使编译缓存查找与构建的其他部分并行运行，而非占用其执行通道。HTTP/2 在一个连接上多路复用多个请求。
- **减少下载量。** Bazel 的 `--remote_download_minimal` 跳过中间输出，而本地缓存层（如 Bazel 的 `--disk_cache` 或 Gradle 的本地构建缓存）无需网络请求即可服务于重复命中。
- **压缩大 blob。** 当缓存支持时，Bazel 的 `--remote_cache_compression` 使用 zstd，这有助于受带宽限制的传输，但对受延迟限制的传输作用不大。

## 常见陷阱 {#common-pitfalls}

- **未声明的输入。** 某个步骤读取了不属于其键一部分的文件、环境变量或工具。缓存随后可能返回基于不同输入构建的输出。在 Gradle 中，声明自定义任务的每个输入；在 Bazel 中，保持操作封闭，并考虑使用 `--incompatible_strict_action_env`，以防止主机 `PATH` 泄露进来。
- **机器特定的键。** 嵌入在输入或输出中的绝对路径、用户名和构建时间戳会导致不同机器间的键不同，从而使远程缓存无法命中。Gradle 的路径敏感性、Bazel 的相对执行路径以及 Xcode 中的 Clang 和 Swift 前缀映射设置旨在消除这些差异。
- **靠近图根部的易变输入。** 将构建号、提交哈希或日期注入到所有模块都依赖的模块中，会导致每次构建时该模块之上的所有内容失效。尽可能晚地注入易变值，理想情况下仅注入到发布构建中。
- **工具链不匹配。** 不同的编译器、JDK 或 Xcode 版本会产生不同的键。这是正确行为，但混合版本的集群实际上会分割缓存。
- **被污染或不可信的写入。** 具有未提交更改或非封闭设置的开发者机器可能会上传其他人随后重用的输出。许多团队只允许受信任分支上的 CI 写入远程缓存，并将其他所有机器设为只读。不可信拉取请求的构建不应写入受信任构建所读取的缓存。
- **忽略传输成本。** 运行耗时 50 毫秒的步骤从远程缓存获取可能花费更长时间。请参阅[延迟、blob 大小和 blob 数量](#latency-blob-size-and-blob-count)。
- **隐藏的测试运行。** 当测试具有确定性时，缓存测试结果是正确的，但这也意味着曾经通过的不稳定测试会在不运行的情况下持续显示为通过。请参阅<.localized_link href="/references/concepts/flaky-test">什么是不稳定测试？</.localized_link>。

## 如何衡量构建缓存 {#how-to-measure-a-build-cache}

缓存的价值在于其端到端节省的内容，而不仅仅是命中率：

- **按工作量加权的命中率。** 统计每个步骤的命中和未命中次数，但根据每个步骤的运行时间进行加权。在廉价步骤上达到 95% 的命中率，可能比在最慢编译步骤上达到 50% 的命中率节省更少的时间。
- **冷构建、温构建和典型构建。** 比较空缓存时的构建、完全预热缓存时的构建以及人们实际运行的构建（例如小幅更改后拉取请求上的 CI）。最后一个才是关键数字。
- **花在缓存本身的时间。** 测量请求数量、延迟、字节数以及下载和上传所花费的时间。如果大部分时间花在等待许多小请求上，那么更近的缓存比更高的带宽更有帮助；如果主要是在移动少数大 blob，则带宽和压缩更为重要。
- **未命中的原因。** 比较两台机器上相同步骤的缓存键。Gradle 可以使用 `-Dorg.gradle.caching.debug=true` 打印每个键背后的输入，Bazel 可以写入执行日志（`--execution_log_compact_file`），你可以对比两次构建的差异，而当 `COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES` 时，Xcode 会在构建日志中报告编译缓存的命中和未命中情况。

## 何时不值得使用 {#when-it-isnt-worth-it}

构建缓存会增加基础设施、安全边界和新的一类 bug。它并不总是合适的工具：

- **小型或快速构建。** 如果干净构建只需一分钟，远程缓存节省的时间很少，而网络往返甚至可能使其变慢。
- **设计上就会未命中的构建。** 如果大多数构建都更改了靠近图根部的输入，那么在修复之前缓存无法提供帮助。先解决失效问题；缓存只能跳过输入匹配的工作。
- **持久性构建机器。** 在同一分支的作业之间保留构建目录的 CI 机器已经获得了增量构建的优势。当机器是临时的、存在许多分支，或者开发者和 CI 应该重用彼此的工作时，共享缓存更有帮助。
- **尚无法修复的非封闭构建。** 偶尔返回错误输出的缓存所消耗的信任成本高于其节省的时间。首先确保你缓存的步骤是可重现的，或者让有问题的步骤不被缓存（例如使用 Bazel 的 `no-remote-cache` 标签）。
- **缓慢或遥远的网络。** 如果缓存距离构建运行的位置很远，在向所有人推广之前请先测量传输时间。

## 使用 Tuist 进行构建缓存 {#build-caching-with-tuist}

[Tuist](https://tuist.dev) 提供一个远程缓存，可插入每个构建系统自身的缓存机制，使开发者机器、CI 和编码代理能够重用彼此的输出，并记录命中、未命中和传输时间，以便你衡量效果：

- <.localized_link href="/guides/features/cache/xcode-cache">Xcode 缓存</.localized_link> 将 Xcode 的编译缓存连接到共享远程缓存，适用于 Xcode 26 或更高版本上的任何 Xcode 项目。
- <.localized_link href="/guides/features/cache/module-cache">模块缓存</.localized_link> 在使用 Tuist 生成的项目中，用预构建的二进制文件替换整个模块。
- <.localized_link href="/guides/features/cache/gradle-cache">Gradle 缓存</.localized_link> 和 <.localized_link href="/guides/features/cache/bazel-cache">Bazel 缓存</.localized_link> 分别作为 Gradle 远程构建缓存和 Bazel 的 Remote Execution API 缓存。
- <.localized_link href="/guides/features/cache">缓存</.localized_link> 列出了所有支持的构建系统，包括 Elixir 和 Struo。
- [缓慢构建](https://tuist.dev/solutions/slow-builds) 是一份实用指南，帮助你在选择缓存之前找到值得移除的工作。
- [构建系统的物理学](https://tuist.dev/blog/2026/08/25/the-physics-of-build-systems) 和 [Kura](https://tuist.dev/blog/2026/09/14/kura) 结合 Tuist 缓存的测量数据，解释了模块缓存、Xcode 编译缓存、Bazel 和 Gradle 之间在工件大小和请求量方面的差异。
