---
{
  "title": "Xcode 缓存",
  "titleTemplate": ":title · 缓存 · 功能 · 指南 · Tuist",
  "description": "通过 Tuist 的 Xcode 缓存集成，加速本地和 CI 上的 Xcode 构建。"
}
---
# Xcode 缓存 {#xcode-cache}

Tuist 支持 Xcode 编译缓存，团队可以借助构建系统的缓存能力共享编译产物。

Xcode 缓存在 Xcode 26 中引入。你也可能看到它被称为 Xcode 构建缓存；它会按输入键重用编译产物，而 Tuist 的远程缓存让这些产物可以在不同机器间共享。

> [!TIP]
> **与模块缓存结合使用**
>
> Xcode 缓存和<.localized_link href="/guides/features/cache/module-cache">模块缓存</.localized_link>在不同粒度级别上工作并相互补充。模块缓存在构建运行前用预构建的`.xcframework`替换整个模块，而 Xcode 缓存在构建过程中重用编译输出。

> [!TIP]
> **在开发者机器上清理时保留`CompilationCache.noindex`**
>
> 默认情况下，编译缓存存储位于`DerivedData`内，因此删除`DerivedData`会将它与构建产物一起清除。在开发者机器上，建议只删除构建产物：重新构建时会从磁盘上的存储重放，无需拉取任何内容。

## 设置 {#setup}

如果你还没有 Tuist 账号和项目，可以通过运行以下命令创建一个：

```bash
tuist init
```

当你拥有一个引用你的`fullHandle`的`Tuist.swift`文件后，可以通过运行以下命令为项目设置缓存：

```bash
tuist setup cache
```

该命令会创建一个[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)，在启动时运行本地缓存服务，Swift [构建系统](https://github.com/swiftlang/swift-build)会使用该服务来共享编译产物。首次在你的开发者机器上运行它，并将其作为每个 CI 任务设置的一部分。

要在 CI 上设置缓存，请确保你已<.localized_link href="/guides/integrations/continuous-integration#authentication">认证</.localized_link>。

### 更新缓存组件 {#updating-the-cache-components}

缓存代理使用稳定的启动器，而不是绑定到上次运行设置的 Tuist 安装路径。安装完成后，`tuist setup cache`和启用缓存的`tuist generate`会将可用目标升级到更新的 Tuist 版本。因此，绑定到较旧 Tuist 的项目不会降级共享代理。生成仅更新现有的启动器目标：它不会安装服务、进行认证、替换插件或重启代理。自定义插件、代理、套接字或注册表覆盖会跳过自动升级。

运行中的代理只有在至少 30 秒没有缓存请求、没有正在进行的请求或后台工作且其发布队列已排空后，才会采用新目标。随后它退出，launchd 启动选定的 CLI，保留服务的参数和凭据环境。只有实际采用目标的代理会以原子方式从其包中刷新磁盘上的插件；在旧代理仍在排空时，设置不会安装更新的插件。如果已安装的插件缺失，显式空闲设置会重启选定的代理以重试刷新。仍然只有一个代理拥有注册表和队列。目标不可用或上传未排空会推迟切换，而不是中断活动请求。凭据刷新会在切换之前跟随选定的 CLI，因此移除较旧的 CLI 安装不会导致等待排空的上传被孤立。

在稳定启动器之前创建的现有安装需要一次显式迁移。在没有构建运行时执行以下操作：

```bash
tuist setup cache
```

完成该迁移后，更新 Tuist 并运行你常用的`tuist generate`即可升级代理和已安装的插件；你无需为每个 CLI 版本重新运行设置。要选择不同的 Xcode（包括在同一路径更新的 Xcode），仍需要显式设置。当共享服务的配置发生变化时，设置可以替换该服务，因此请先等待机器上的所有构建完成。代理同时支持之前的插件协议和当前协议，因此 Xcode 中已加载的兼容插件在代理升级后仍可正常工作。完全退出并重新打开 Xcode 以加载最新插件，但已加载的兼容插件不需要立即重启。当某个版本更改了生成的构建设置时，请重新生成项目。

保持所选的 Tuist 安装可用：启动器会使用它进行启动、配置和凭据刷新。一旦启动器升级完成，就可以移除较旧的安装。如果所选可执行文件已被删除或不再可执行，`tuist setup cache`可以使用可用的安装（甚至是较旧的版本）修复目标，而无需先拆除缓存。稳定的可执行文件别名在包管理器升级期间会保留；仅在比较安装身份时才会解析符号链接。启动时，代理会记录实际启动的版本，包括就地更新或故意回滚，同时保留使用的最高版本，以防止不相关的旧检出切换可用的安装。

没有发布版本的源码构建 CLI 以及显式的`TUIST_CAS_PLUGIN_PATH`或`TUIST_CAS_PROXY_PATH`设置会使用显式启动配置，而不是自动版本选择。重建这些组件后请重新运行设置。设置会检查它们的新鲜度，并仅在替代品就绪后才禁用受管目标升级。

`tuist teardown cache`会在移除启动器目标之前停止服务，同时为现有项目保留稳定插件。如果停止服务失败，其启动器仍可用于重启和再次尝试拆除。成功拆除后，生成无法重新创建该服务。

### 配置 Xcode 构建设置 {#configure-xcode-build-settings}

对于现有的 Xcode 项目，将`tuist setup cache`打印的构建设置复制到项目的构建设置或现有的`.xcconfig`文件中。该命令会打印你账号的配置；它不会生成配置文件或编辑你的 Xcode 项目。在扩展`OTHER_SWIFT_FLAGS`时保留`$(inherited)`，以便保留其他编译器选项。

设置包括：

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_PLUGIN_PATH = $HOME/.local/state/tuist/libtuist_cas_plugin.dylib
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/cas-proxy.sock
COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
OTHER_SWIFT_FLAGS = $(inherited) -cas-plugin-option tuist-instance=your-org/your-project
```

请注意，`COMPILATION_CACHE_ENABLE_PLUGIN`、`COMPILATION_CACHE_PLUGIN_PATH`、`COMPILATION_CACHE_REMOTE_SERVICE_PATH`和`COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES`需要作为**用户定义的构建设置**添加，因为它们未在 Xcode 的构建设置 UI 中直接公开。

> [!NOTE]
> **插件路径**
>
> `libtuist_cas_plugin.dylib`是随 Tuist 一起提供的编译缓存插件，位于`tuist`可执行文件旁边。`tuist setup cache`将其复制到`$HOME/.local/state/tuist/libtuist_cas_plugin.dylib`，而`COMPILATION_CACHE_PLUGIN_PATH`指向该副本。该路径在每台机器上都相同，且在更新 Tuist 时不会改变，因此你可以将该设置与项目一起提交。设置和新启动的代理会从所选的 Tuist 捆绑包中刷新该副本；从较旧的检出运行设置不会降级较新的插件。

> [!NOTE]
> **每个项目使用同一个套接字**
>
> `tuist setup cache`在每台机器上安装一个缓存代理，因此每个项目都使用相同的`COMPILATION_CACHE_REMOTE_SERVICE_PATH`。`tuist-instance`插件选项用于标识项目。

> [!IMPORTANT]
> **`COMPILATION_CACHE_REMOTE_SERVICE_PATH`负责共享 C 和 Objective-C**
>
> 人们很容易将此设置理解为“缓存服务的位置”并将其视为可选。它也是决定 C、Objective-C、预编译模块和预编译头文件是否共享的开关：只有在配置了远程缓存服务时，构建系统才会为这些内容运行缓存。如果不包含它，Swift 编译仍然可以共享，但在任何尚未构建过该项目的机器上，每个 C/Objective-C 文件和每个模块都会重新编译。

> [!NOTE]
> **并发缓存查找**
>
> `COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES`会让构建系统为每次编译执行的远程缓存查找与构建的其余部分并行运行，而不是在构建的执行通道上每次只运行少数几个。如果构建从远程缓存中未命中或恢复了大量编译，则会更快完成。

你也可以在运行`xcodebuild`时通过添加以下标志来指定这些设置，例如：

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_PLUGIN_PATH=$HOME/.local/state/tuist/libtuist_cas_plugin.dylib \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/cas-proxy.sock \
    COMPILATION_CACHE_ENABLE_DETACHED_KEY_QUERIES=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES \
    'OTHER_SWIFT_FLAGS=$(inherited) -cas-plugin-option tuist-instance=your-org/your-project'
```

> [!NOTE]
> **Xcode 27 及更高版本上的前缀映射**
>
> 在 Xcode 27 及更高版本上，`tuist setup cache`还会打印`SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING`和`CLANG_ENABLE_PROJECT_PREFIX_MAPPING`。它们使编译缓存键独立于项目和`DerivedData`的位置。将它们添加为用户定义的构建设置。启用它们会更改每个缓存键，因此下一次构建会再次填充缓存。当`enableCaching`开启时，`tuist generate`会为你设置它们。
>
> 编译器还会将映射的路径写入代码覆盖率数据，而 Xcode 无法解析它们，因此覆盖率报告会遗漏所有使用前缀映射编译的源文件。打印的设置以及`TUIST_PREFIX_MAPPING_FOR_COVERAGE_*`设置会在收集代码覆盖率的构建中关闭前缀映射。`tuist generate`也会执行相同的操作。这些构建仍然使用编译缓存，但它们的缓存键取决于项目和`DerivedData`路径。
>
> 当你在命令行上将这些设置传递给`xcodebuild`时，请用单引号括起包含`$(...)`的值，如上面的`OTHER_SWIFT_FLAGS`所示。否则，shell 会将它们展开为空字符串，从而关闭前缀映射：
>
> ```
> xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
>     'SWIFT_ENABLE_PREFIX_MAPPING=$(TUIST_PREFIX_MAPPING_FOR_COVERAGE_$(CLANG_COVERAGE_MAPPING))' \
>     SWIFT_ENABLE_PROJECT_PREFIX_MAPPING=YES \
>     'CLANG_ENABLE_PREFIX_MAPPING=$(TUIST_PREFIX_MAPPING_FOR_COVERAGE_$(CLANG_COVERAGE_MAPPING))' \
>     CLANG_ENABLE_PROJECT_PREFIX_MAPPING=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_NO=YES \
>     TUIST_PREFIX_MAPPING_FOR_COVERAGE_YES=NO
> ```

> [!NOTE]
> **生成的项目**
>
> 如果你的项目由 Tuist 生成，则无需手动设置这些设置。
>
> 在这种情况下，你只需在`Tuist.swift`文件中添加`enableCaching: true`：
> ```swift
> import ProjectDescription
>
> let tuist = Tuist(
>     fullHandle: "your-org/your-project",
>     project: .tuist(
>         generationOptions: .options(
>             enableCaching: true
>         )
>     )
> )
> ```

### 带前缀映射的覆盖率 {#coverage-with-prefix-mapping}

默认情况下，生成的项目会为覆盖率构建禁用前缀映射，以保持 Xcode 的覆盖率报告和`xccov`正常工作。你可以启用它以使覆盖率编译在不同检出之间可共享：

```swift
let tuist = Tuist(
    project: .tuist(
        generationOptions: .options(
            enableCaching: true,
            coverage: .coverage(prefixMapping: true)
        )
    )
)
```

`TUIST_COVERAGE_PREFIX_MAPPING`环境变量（`1`或`0`）优先于`prefixMapping`。此选项适用于 Xcode 27 及更高版本，并且需要`enableCaching`。覆盖率`tuist test`上传支持它：Tuist 使用`llvm-cov`测量运行，后者读取具有映射路径的源文件，并将它们关联回你仓库中的文件。Xcode 自身的覆盖率报告和`xccov`仍可能遗漏这些源文件，如果`llvm-cov`导出失败，回退到结果包的`xccov`报告的上传也可能遗漏它们。映射的`#filePath`值还可能影响相对于源文件定位夹具的测试；请改为通过显式的运行时检出路径解析夹具。如果你自行处理覆盖率，请将每个插桩二进制文件与其目标的`$(TARGET_TEMP_DIR)/compilation-prefix-map.json`配对，后者将虚拟前缀映射回本地目录。当启用每项目映射时，不要为每个二进制文件重用同一个目标的映射。

覆盖率前缀设置会参与二进制缓存和选择性测试哈希的计算，因为它们控制写入覆盖率工件的路径。更改此选项或以不同方式设置`TUIST_COVERAGE_PREFIX_MAPPING`会使这些哈希失效，即使是普通构建也是如此。如果开发者和 CI 作业应共享二进制缓存和选择性测试结果，请保持该值一致。

### 调试生成的项目 {#debugging-generated-projects}

恢复的本机模块需要链接的调试信息以及对编译缓存的访问权限。Tuist 会使用 dSYM 和每切片源身份元数据预热 Debug 和 Release 模块，然后在替换目标之前根据使用者声明的源验证元数据。缺少或不兼容的元数据会保留该目标的源。脚本生成的`.generated(...)`源具有声明指纹，而非可验证的内容校验和，因此这些目标保持从源构建，且不会发布到本机模块缓存。具有实际内容校验和的生成资源访问器仍然符合条件。不支持的调试信息会跳过受影响目标的发布，而不会阻塞不相关的产品；源变更和取消仍会导致预热失败。缓存格式已更改，因此由旧版本预热的工件需要重新预热。

对于经过验证的替换，Tuist 会在消费者拥有的 dSYM UUID plist 中准备源重定位，并为静态缓存代码链接仅调试的伴生文件。它不会重写缓存的二进制文件，也不会在 LLDB 的持久全局源映射中安装生产者源路径。显式的调试器初始化器和模块加载器设置仍然具有权威性。调试符号和源重定位不会修复相对于源的运行时文件访问或原生 Xcode 覆盖率报告；覆盖率变体选择和 LLVM 导出仍然是单独的功能。

启用 `enableCaching: true` 后，Tuist 会为 Run 和 Test 操作配置 LLDB 源映射。如果某个操作具有自定义 LLDB 初始化器，Tuist 会先写入已解析的源映射，然后加载自定义初始化器，以便其扩展或覆盖该映射。否则，它会先加载 `~/.lldbinit-Xcode`（如果文件存在），回退到 `~/.lldbinit`，然后再替换源映射。它只加载一个主目录文件，从而恢复每个用户的调试器设置而不会重复加载。替换操作会移除之前运行中过时的映射，并优先于主目录文件中的源映射；应将需要保留的源映射条目放在操作的自定义初始化器中。其他主目录设置会被保留。Tuist 的缓存特定模块搜索路径、加载器设置和 Clang 标志随后应用，并优先于这些设置的用户值。主目录文件的错误仍然可见，但不会阻止后续命令加载，且命令不会被回显。即使没有 `enableCaching` 且在较早版本的 Xcode 上，当 Tuist 为从模块缓存恢复的二进制文件配置调试时，此初始化器保留机制同样适用。

在 Xcode 27 及更高版本中，除非项目明确设置，否则生成的项目会关闭 Xcode 的每项目前缀映射（`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING` 和 `CLANG_ENABLE_PROJECT_PREFIX_MAPPING`）。它们的前缀（例如 `/^src`）在每个项目中指向不同的目录，LLDB 仅针对被调试目标的项目解析这些前缀。相反，源记录在工作区范围的前缀下：`/^root` 用于 Tuist 根目录，`/^spm` 用于 Swift 包暂存目录，`/^intermediates` 和 `/^products` 用于构建输出。每个前缀在所有项目中都指向同一个目录，因此断点可以解析工作区中任何项目的源。

Tuist 根目录之外的路径不会被映射。根目录之外项目的缓存键取决于其检出位置，因此其他检出环境和机器无法命中其缓存。为了使其缓存键独立于检出位置，请在该项目的清单中开启每项目映射：

```swift
let checkoutIndependentSettings = Settings.settings(base: [
    "SWIFT_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
    "CLANG_ENABLE_PROJECT_PREFIX_MAPPING": "YES",
])
```

将这些设置传递给该 `Project`。当你调试来自另一个项目的目标时，LLDB 将无法找到该项目的源。清单中的项目基础设置优先于项目级别的 xcconfig 值，因此请直接在清单中设置它们。

更改这些设置会改变编译缓存键、二进制缓存哈希和选择性测试哈希，因此这些缓存需要重新预热。请在整个团队中保持选择一致。

### 缓存上传策略 {#cache-upload-policy}

默认情况下，缓存服务既下载又上传工件到远程缓存。你可以通过 `Tuist.swift` 文件中的 `xcodeCache` 选项来控制此行为，以启用只读模式，在该模式下工件会被下载但永远不会上传：

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        upload: false
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

一种常见的模式是仅从 CI 推送工件，因为那里的构建是可重现的，同时保持本地环境为只读。你可以使用 `Environment.isCI` 来实现这一点，它会检查大多数 CI 提供商设置的 `CI` 环境变量：

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        upload: Environment.isCI
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

通过此设置，本地构建可以从缓存工件中受益而无需上传，而 CI 构建则为团队的其他成员填充缓存。

上传策略按项目在运行 `tuist setup cache` 的机器上记录。要更改它，请更新 `upload` 并再次运行 `tuist setup cache`，如果 Tuist 生成你的项目，还需运行 `tuist generate`。之后的上传将遵循新策略，无需重启该机器的缓存。在同一台机器上同时运行的同一项目的作业共享其策略，因此最近的 `tuist setup cache` 决定所有作业的策略。

### 存储大小限制 {#store-size-limit}

编译缓存存储会随着每次构建而增长。为了限制项目的存储大小，请在 `Tuist.swift` 文件中设置 `storeSizeLimit`：

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    xcodeCache: .xcodeCache(
        storeSizeLimit: .gigabytes(20)
    ),
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```

在没有构建运行时，Tuist 每 10 分钟检查一次项目的每个存储。一旦较新的构建写入了大约一半的限制容量，它就会删除存储中最旧的缓存输出，从而使存储稳定在限制大小附近。在构建运行时，存储可能会超过限制；如果在设置限制时存储已经较大，一旦新构建写入足够多的数据，存储就会缩小。当多个项目使用同一个存储（如默认位置那样）时，适用其中最小的限制。该限制适用于你运行 `tuist setup cache` 的每台机器，因此在更改限制后请再次运行它。

### 模块缓存哈希 {#module-cache-hashes}

编译缓存设置不属于<.localized_link href="/guides/features/projects/hashing">模块缓存哈希</.localized_link>的一部分。Tuist 会将每个 `COMPILATION_CACHE_*` 构建设置以及每个带有其值的 `-cas-plugin-option` 标志排除在哈希之外。开启或关闭 `enableCaching`，或更改上传策略，会保留目标的哈希，因此你已经预热的<.localized_link href="/guides/features/cache/module-cache">模块缓存</.localized_link>二进制文件仍然有效。你可以针对相同的模块缓存比较开启和关闭 Xcode 缓存的构建。

> [!NOTE]
> **前缀映射设置会被哈希化**
>
> 在 Xcode 27 及更高版本中，`enableCaching: true` 还会设置 `SWIFT_ENABLE_PREFIX_MAPPING`、`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`、`CLANG_ENABLE_PREFIX_MAPPING`、`CLANG_ENABLE_PROJECT_PREFIX_MAPPING` 和 `TUIST_PREFIX_MAPPING_FOR_COVERAGE_*` 设置。这些设置是模块缓存哈希的一部分，因此在 Xcode 27 及更高版本中，开启或关闭 `enableCaching` 会改变目标的哈希。

### 重用大型输出的部分 {#reusing-parts-of-large-outputs}

Xcode 缓存可以通过内容定义分块来减少传输量。它不再将每个大型输出视为与早期版本无关，而是根据其内容在边界处分割压缩后的输出。编辑后，即使偏移量发生变化，也可以重用匹配的块。

上传仅发送服务器缺失的块。下载首先获取精确的缓存操作和输出的分块配方，然后重用存储在本地机器上的已验证块并获取缺失的部分。完整的重建输出在恢复到编译器缓存之前会经过验证。

传输分块缓存与 `DerivedData` 分开，因此其分块可以在清理编译缓存或重启本地缓存服务后保留。它是可丢弃的，分块负载最多限制为一 GiB，另有一个最多两 MiB 的临时暂存文件。被淘汰或损坏的分块会在需要时重新下载。保留编译缓存本身仍然比重建其内容更快。

仅当服务器通告兼容支持时，客户端才会使用分块传输。较旧的客户端仍可读取完整输出，而连接到较旧或不支持的服务器的客户端则保留普通传输。小型输出仍沿用现有的完整输出路径。

这会减少传输的字节数，但不会减少编译器失效。更改源文件可能仍需要编译；分块有助于发布或恢复生成的输出。节省量取决于输出和编辑内容，没有匹配分块的冷启动机器必须下载整个输出。

### 持续集成 {#continuous-integration}

要在 CI 环境中启用缓存，你需要运行与本地环境相同的命令：`tuist setup cache`。

对于身份验证，你可以使用<.localized_link href="/guides/server/authentication#oidc-tokens">OIDC 身份验证</.localized_link>（推荐用于受支持的 CI 提供商），或者通过 `TUIST_TOKEN` 环境变量使用<.localized_link href="/guides/server/authentication#account-tokens">账户令牌</.localized_link>。

使用 OIDC 身份验证的 GitHub Actions 工作流示例：
```yaml
name: Build

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist setup cache
      - # Your build steps
```

请参阅<.localized_link href="/guides/integrations/continuous-integration">持续集成指南</.localized_link>以获取更多示例，包括基于令牌的身份验证以及其他 CI 平台，如 Xcode Cloud、CircleCI、Bitrise 和 Codemagic。

### CI 上的编译缓存存储 {#compilation-cache-store-on-ci}

编译缓存存储是 Xcode 保存编译输出的本地目录。`COMPILATION_CACHE_CAS_PATH` 构建设置用于设置其位置，默认为 `DerivedData` 内的 `CompilationCache.noindex`。

#### 有状态存储 {#stateful-store}

若要在构建之间保留存储，请将 `COMPILATION_CACHE_CAS_PATH`（以及 `tuist cache` 的 `TUIST_COMPILATION_CACHE_CAS_PATH`）指向一个持久路径，并使用[存储大小限制](#store-size-limit)限制其大小。

## 故障排除 {#troubleshooting}

### 构建警告 Xcode 缓存代理失败 {#cas-proxy-failed}

如果构建显示如下警告，Xcode 会根据哪个编译首先遇到失败而加上 `CAS error:` 或 `CAS operation failed:` 前缀：

```
warning: CAS error: The Tuist Xcode cache proxy at /Users/you/.local/state/tuist/cas-proxy.sock failed (proxy connect: No such file or directory (os error 2)). Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run `tuist setup cache` if the proxy is not running.
```

则编译缓存无法访问由 `tuist setup cache` 安装的本地缓存代理。构建仍然成功，但受影响的编译无法获得远程缓存命中，因此其行为类似于空缓存构建。它们的上传内容会保留在磁盘上，并在代理再次处理请求时发送：如果及时恢复，则在同一构建的稍后阶段发送；否则将在同一台机器的下一次构建期间发送。作业结束后被丢弃的 CI 机器会丢失这些内容。该警告在每个构建中仅出现一次，显示在 Xcode 的问题导航器和 `xcodebuild` 输出中。

要检查代理是否正在运行，请查找监听警告中所述套接字的进程：

```bash
lsof ~/.local/state/tuist/cas-proxy.sock
```

如果命令未打印任何内容，请运行 `tuist setup cache` 以重新启动代理。在 CI 上，请在每个作业中的任何 `xcodebuild` 调用之前运行 `tuist setup cache`。

### 构建极其缓慢并发出 `CAS error: deadlineExceeded` 警告 {#cas-deadline-exceeded}

如果你的构建耗时远超预期，且 Xcode 构建日志中充满如下警告：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): No such file or directory (errno: 2)))
note: cache key query failed
```

或：

```
Warning: CAS error: deadlineExceeded(connectionError: Optional(connect(descriptor:addr:size:): Connection refused (errno: 61)))
```

则 `COMPILATION_CACHE_REMOTE_SERVICE_PATH` 指向一个无人监听的套接字，通常是早期版本的 Tuist 配置的每项目套接字（`~/.local/state/tuist/<org>_<project>.sock`）。Tuist 不再提供该套接字服务。Xcode 会在每次编译缓存请求时重试连接，而不是快速失败，这可能导致构建耗时一小时或更久，而 Tuist 无法改变这种行为。

修复方法：

- **生成的项目**：再次运行 `tuist generate`。
- **其他项目**：将 `COMPILATION_CACHE_*` 构建设置替换为 `tuist setup cache` 打印的设置，如[配置 Xcode 构建设置](#configure-xcode-build-settings)中所述。

如果你不使用 Xcode 缓存，请改为移除 `COMPILATION_CACHE_*` 构建设置并运行 `tuist teardown cache`。

### 即使禁用了上传，本地仍出现 `uploaded CAS output` {#uploaded-cas-output-with-upload-disabled}

当设置 `xcodeCache: .xcodeCache(upload: false)`（或在非 CI 机器上设置 `upload: Environment.isCI`）时，你仍可能在构建日志中看到 `note: uploaded CAS output ...`。`xcodebuild` 无法跳过这些调用，因此 Tuist 仍会接收它们，但不会向 Tuist 服务器发布任何内容。仪表板指标已考虑此情况，因此不会报告虚假的上传流量。
