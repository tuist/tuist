---
{
  "title": "Rust 缓存",
  "titleTemplate": ":title · 缓存 · 功能 · 指南 · Tuist",
  "description": "通过 Cargo 在本地和 Tuist 远程缓存中复用受支持的 Rust 编译产物。"
}
---
# Rust 缓存 {#rust-cache}

Tuist 会缓存受支持的 Rust 编译产物，以便在 Cargo 的构建产物被移除后重新利用。该缓存内置于 Tuist CLI 中，无需安装单独的缓存可执行文件或 Cargo 插件。

<!-- @snippet: ./_rust-experimental -->

## 启用缓存 {#enable-caching}

按照<.localized_link href="/guides/get-started/rust-project">Rust 项目设置</.localized_link>连接你的项目并完成身份验证。然后通过 Tuist 运行构建：

```sh
tuist cargo build --release
```

符合条件的编译会自动使用缓存。无需额外的缓存配置或启用标志。Tuist 会根据你现有的项目和服务器配置，发现你账户的缓存端点并获取缓存凭据。

如果你使用 mise，请<.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">配置 Cargo 包装器</.localized_link>，以便继续输入普通的 `cargo` 命令。

## 工作原理 {#how-it-works}

在 Cargo 启动之前，Tuist 会恢复由先前构建使用相同工具链、配置文件和配置生成的注册表和 git 依赖的产物，这样 Cargo 就会认为它们是最新的。Cargo 仍负责决定需要重新构建的内容。随后，对于 Cargo 仍然执行的每个符合条件的编译，Tuist 会：

1. 检查本地缓存中是否存在匹配的产物。
2. 如果本地未命中，则通过远程执行 API（REAPI）查询 Kura，下载缺失的内容，并在恢复之前验证产物。
3. 如果缓存未命中，则正常运行编译器。编译成功后，它会将产物存储在本地，并在获得授权时通过 REAPI 上传到 Kura。只有在其引用的所有内容都可用后，才会发布远程缓存条目。

同一台机器上的构建共享本地缓存，包括其他工作树或目标目录中的构建。当另一个构建已经在编译同一个 crate 或运行相同的构建脚本时，Tuist 会等待它完成并恢复其产物，而不是重复执行相同的工作。如果该构建耗时超过 10 分钟，Tuist 将停止等待并自行编译该 crate。

本地构建和 CI 构建使用相同的远程缓存协议。读写访问权限来自 Tuist 服务器颁发的缓存凭据以及你账户的<.localized_link href="/guides/features/cache#restrict-uploads-to-ci">缓存上传策略</.localized_link>。账户可以允许开发者下载，同时将上传限制为仅限 CI 和账户令牌。缓存写入者是受信任的代码生产者：缓存的编译器产物是可执行代码，因此只向你信任的机器和令牌授予写入权限。

如果远程设置失败，本地缓存仍然可用。不可用、缺失或损坏的缓存条目会回退到编译。上传失败不会导致构建失败，也不会丢弃其本地缓存条目。

## 哪些内容可以被缓存 {#what-can-be-cached}

缓存支持：

- 库 crate，包括工作区和路径 crate、带有依赖项的 crate 以及带有生成源代码的 crate。Tuist 根据编译器读取的源代码对它们进行键控。
- `cargo check` 和 `cargo clippy`，它们仅将库编译为元数据。它们的条目与构建的条目是分开的，因此 check 永远不会为 `cargo build` 提供库。`cargo clippy` 使用普通编译器编译的依赖项（例如工作区之外的路径 crate）会复用 `cargo check` 的条目。
- 在 Apple silicon Mac 以及带有 glibc 的 x86_64 和 arm64 Linux 上，对于源代码检查无法预先键控的编译，例如使用过程宏、内联汇编或原生库的 crate、过程宏本身以及链接的可执行文件。Tuist 会记录每个编译读取的文件、环境变量和只读命令（例如 `git describe`），并据此进行键控。在 Linux 上，系统链接器、C 库以及链接读取的启动文件都是其键的一部分。
- 在同一平台上，构建脚本的运行，包括它们执行的 C 编译（在 macOS 上使用默认的 Apple 编译器，在 Linux 上使用任何动态链接的编译器）。只有当它读取的文件、环境和命令保持不变时，才会恢复运行。
- 警告和其他诊断信息，缓存的 crate 会再次显示这些信息，包括 Clippy 的 lint。

以下内容仍会正常构建：

- 在没有 glibc 的 Linux 发行版（例如 Alpine）上的构建脚本和记录的编译。
- 连接到网络、启动 Tuist 无法观察的程序（在 Linux 上为静态链接程序）或在输出目录之外写入的构建脚本。
- 增量编译、自定义目标，以及不受支持的编译器参数或源代码输入。
- 过程宏和构建脚本的 Clippy 编译，以及启用 `cargo` lint 组的 Clippy 运行，后者通过 `cargo metadata` 读取工作区的每个清单及其锁文件。
- 产生意外编译器输出的编译。
- 使用动态加载器设置（例如 `LD_PRELOAD`）运行的编译，或者使用位于 Rust 工具链和目标目录之外的 `LD_LIBRARY_PATH` 目录运行的编译，例如从你的 shell 继承的目录或位于目标目录之外的 `build.build-dir`。

预先存在的全局编译器包装器会禁用 Tuist 的编译缓存和编译器观察者。除 Clippy 之外的自定义工作区包装器也会绕过缓存。请参阅<.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">编译器工具兼容性</.localized_link>。

缓存键包括包内容、编译器和工具链、参数以及构建环境。Clippy 条目还取决于 Clippy 版本、`CLIPPY_ARGS`、`CLIPPY_CONF_DIR`、`CLIPPY_DISABLE_DOCS_LINKS` 中的 lint 参数、包的 `Cargo.toml`，以及 Clippy 加载的 `clippy.toml` 或 `.clippy.toml`。检出目录、目标目录、Cargo home 和工具链位置会被替换为占位符，因此不同路径下的检出可以复用相同的条目。如果某个 crate 的输出嵌入了其自身路径（例如通过 `env!("CARGO_MANIFEST_DIR")`），则仅在该路径下复用。凭据、Tuist 报告设置以及已识别的 CI 运行元数据不会使条目失效。在编译期间读取这些排除变量的 crate 不会被缓存。

## 验证复用 {#verify-reuse}

Cargo 已经避免重新构建最新的产物。为了测试 Tuist 的缓存而不是依赖 Cargo 的现有产物，请构建一次，移除 Cargo 的产物，然后重复相同的构建：

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

符合条件的库可以在第二次构建时恢复；不受支持的 crate 仍会编译。移除 Cargo 的产物不会删除 Tuist 独立的本地缓存。这检查的是复用情况，不一定是远程下载：本地命中不需要从 Kura 传输。输入验证和缓存操作会增加开销，因此避免编译并不能保证小型 crate 的构建更快。

为了检查命中是否正确（例如作为 CI 中的金丝雀测试），将任一变量设置为 `sampled`（每 64 个 crate 中有一个，每次构建都是相同的 crate）或 `always`：

- `TUIST_CARGO_VERIFY` 检查命中所依据的输入是否仍然是编译器或构建脚本读取的内容。
- `TUIST_CARGO_VERIFY_RECOMPILE` 重新编译命中的内容，并将其输出与缓存的输出进行比较。

被检查的 crate 会进行编译而不是恢复，就像它未被缓存一样，因此其输出始终是最新的，且验证不会改变构建结果。验证永远不会存储或替换被检查 crate 的缓存条目。如果其最新输出与缓存的输出不同，依赖它的 crate 将会未命中，并像未缓存构建那样被缓存。增量编译不可复现，因此对于这些情况，`TUIST_CARGO_VERIFY_RECOMPILE` 仅比较元数据和依赖信息。使用 `TUIST_DEBUG=1` 时，每次检查都会打印一行 `Tuist Cargo cache: verified`，发现差异的检查会被计为构建缓存测量中的分歧。

## 检查缓存活动 {#inspect-cache-activity}

在项目仪表板中打开 **Cargo 缓存**，以检查命中率、记录的传输、延迟、吞吐量和最近的构建。打开构建的 **缓存** 选项卡，查看单个任务决策和 CAS 输出。

缺失的测量值不计为零，缓存命中不一定意味着远程下载。详情请参阅 <.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust 缓存测量</.localized_link>。

## 故障排除 {#troubleshooting}

启用调试输出以检查缓存传输和报告失败：

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

调试输出还会解释为什么未存储编译或构建脚本运行。如果你没有看到任何命中，请检查是否有其他编译器包装器优先生效，以及编译器、标志和环境是否与填充缓存的构建匹配。对于远程上传，还需检查身份验证和账户的缓存上传策略。
