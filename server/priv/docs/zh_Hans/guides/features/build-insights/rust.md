---
{
  "title": "Rust 构建洞察",
  "titleTemplate": ":title · 构建洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 中查找耗时较长的 crate，比较构建性能，并检查 Rust 编译器警告和错误。"
}
---
# Rust 构建洞察 {#rust-build-insights}

构建洞察帮助你找出拖慢 Cargo 构建速度的原因，并在影响整个团队之前捕捉回归问题。你可以将本地构建与 CI 构建进行比较，查看构建时间的变化，并检查每次构建中编译的 crate。

> [!IMPORTANT]
> **要求**
>
> - 按照<.localized_link href="/guides/get-started/rust-project">Rust 项目设置</.localized_link>连接你的项目并进行身份验证。

## 报告你的构建 {#report-your-builds}

通过 Tuist 运行你常用的 Cargo 命令：

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo +nightly build --features tracing
```

如果你使用 mise，请<.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">配置 Cargo 包装器</.localized_link>以继续使用普通的 `cargo` 命令。你的参数、工具链选择、输出和退出代码保持不变。

## 找出拖慢构建速度的原因 {#explore-your-builds}

在仪表板的**构建 → 构建运行**中打开一个构建。使用日期、环境和 Rust 版本过滤器来比较类似的构建。构建及其缓存计数也可以通过 `tuist build cargo list` 和 `tuist build cargo show`、`GET /api/projects/{account_handle}/{project_handle}/cargo/builds` 以及 `list_cargo_builds` 和 `get_cargo_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link> 获取。

在**概览**中，使用**编译器作业**查找缓慢的 crate。按**持续时间**或**开始于之后**（自 Cargo 命令启动以来的时间）排序，或按 crate 名称或根源文件搜索。

每一行代表对一个 crate 的一次 `rustc` 调用，该 crate 可能包含多个源文件。**Crate 根目录**标识其根源文件；持续时间是针对整个编译器作业的，而不仅仅是该文件。一个 crate 可能因不同的目标或配置而出现多次。编译器消息分组在**警告**和**错误**中。

### 跨构建跟踪 crate {#crate-history}

当对你的项目可用时，**构建 → Crates** 显示观察到的 crate 及其编译历史。打开一个 crate 以比较其在不同构建中记录的持续时间和结果，然后追溯编译回到其 Cargo 构建。相同的清单也可通过项目 API 中的 `/cargo/crates` 和带有 `kind: cargo_crates` 的共享 MCP 构建实体工具获得。

Crate 按其确切记录的根路径、名称和类型进行分组。更改检出路径可能会拆分历史记录；配置文件、功能和目标三元组不做区分。这是观察到的编译器作业的清单，而不是工作区中的每个 crate。已缓存或最新的 crate 不会创建编译样本。

### 归属构建报告 {#report-attribution}

经过身份验证的报告可识别个人凭证背后的个人。共享凭证无需识别个人。可以选择将 `TUIST_ACTOR_ID` 设置为报告机器上的稳定不透明标识符；默认情况下它是关闭的，并显示为未经声明的索赔，从不用于授权。较旧的服务器可能会忽略该索赔。不要在其中放置秘密。

## 阅读计时信息 {#timing-boundaries}

构建持续时间是整个 Cargo 命令所花费的时间。编译器作业可以并行运行，因此它们的持续时间加起来不等于构建持续时间。

Cargo 仅编译需要重新构建的 crate。已经最新的 crate 不会出现在编译器列表中。使用 Tuist 的编译缓存时，恢复的作业会出现在缓存测量中，而不是作为编译器执行。

Tuist 不单独测量构建脚本，也不显示构建时间线。大型构建显示前 500 个编译器作业，如果记录了更多作业，则会显示通知。

## 阅读缓存测量数据 {#cache-measurements}

`tuist cargo` 包含一个在 Tuist CLI 中实现的实验性编译缓存。请遵循<.localized_link href="/guides/features/cache/rust">Rust 缓存指南</.localized_link>进行设置、通过 Kura 进行远程读写、支持的编译以及故障排除。

在项目侧边栏中打开**Cargo 缓存**，以跟踪缓存命中率以及跨构建记录的传输、延迟和吞吐量测量数据。按日期或环境过滤，在每日趋势和单个构建命中率之间切换，或打开最近的构建以检查其缓存活动。没有缓存测量数据的构建保持不可用状态，而不是计为零。

打开构建的**缓存**选项卡以查看任务命中、任务未命中、命中率以及下载和上传的字节数。当构建报告缓存数据时，该选项卡会出现。

- **可缓存任务**显示哪些编译器和构建脚本任务重用了缓存的输出。搜索或过滤任务，检查缓存读/写延迟，并展开一行以查看其输出。
- **CAS 输出**显示工件的下载和上传，包括它们的大小、持续时间和吞吐量。图表统计完成的传输；已存在的工件和失败的尝试仍保留在表中。

**命中**表示重用了缓存的输出。**未命中**表示任务进行了编译。命中不分本地和远程；CAS 输出显示记录的工件操作。

如果详细记录缺失或不完整，页面会显示通知。摘要仍然涵盖整个构建。估计避免的编译器工作**不是节省的构建耗时**。

<!-- @snippet: ../cache/_rust-experimental -->

增量编译正常构建。

### 运行测试的构建 {#builds-that-run-tests}

`tuist cargo test` 报告整个命令的持续时间，包括其测试。它还通过<.localized_link href="/guides/features/test-insights/rust">Rust 测试洞察</.localized_link>报告单独的测试结果，包括文档测试。单独的测试结果出现在**测试**下；命令持续时间出现在构建洞察中。

## 其他编译器工具 {#other-compiler-tools}

Tuist 保留通过 `RUSTC_WRAPPER`、`CARGO_BUILD_RUSTC_WRAPPER` 或 Cargo 配置配置的现有编译器包装器，并保持 `RUSTC_WORKSPACE_WRAPPER` 不变。预先存在的全局包装器会禁用 Tuist 的缓存和编译器观察者：Tuist 无法确定该包装器是否实际运行了 rustc。自定义工作区包装器同样可能导致报告中显示的编译器作业较少。

Tuist 通过 rustup 找到 Cargo。如果你使用自定义安装，请将 `TUIST_CARGO_EXECUTABLE` 设置为其可执行文件路径。通过直接工具链路径调用 Cargo 会绕过 mise 的包装器。Cargo 别名不能替换内置命令，例如 `build`。

如果你使用 Cargo 的夜间版 `-C` 选项，请先切换到工作区：Tuist 转发 `-C` 命令，但不收集它们的构建计时。

## 故障排除 {#troubleshooting}

如果构建未出现在仪表板中，请启用调试输出以查看为何未发送其报告：

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

报告不会改变你的构建结果。
