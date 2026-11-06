---
{
  "title": "Rust 构建洞察",
  "titleTemplate": ":title · 构建洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 中查找耗时较长的 crate，比较构建性能，并检查 Rust 编译器的警告和错误。"
}
---
# Rust 构建洞察 {#rust-build-insights}

Build Insights 帮助你找出拖慢 Cargo 构建的因素，并在影响整个团队之前捕捉回归问题。你可以将本地构建与 CI 构建进行对比，查看构建时间的变化，并检查每次构建中编译的 crate。

> [!IMPORTANT] Requirements
> - 按照 <.localized_link href="/guides/get-started/rust-project">Rust 项目设置</.localized_link> 连接你的项目并完成身份验证。

## 上报你的构建 {#report-your-builds}

通过 Tuist 运行你常用的 Cargo 命令：

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo +nightly build --features tracing
```

如果你使用 mise，请 <.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">配置 Cargo 包装器</.localized_link> 以继续使用普通的 `cargo` 命令。你的参数、工具链选择、输出和退出码保持不变。

## 找出拖慢构建的因素 {#explore-your-builds}

在仪表板的 **Builds → Build Runs** 中打开一个构建。使用日期、环境和 Rust 版本过滤器来比较相似的构建。你也可以通过 `tuist build cargo list` 和 `tuist build cargo show`、`GET /api/projects/{account_handle}/{project_handle}/cargo/builds`，以及 `list_cargo_builds` 和 `get_cargo_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link> 获取构建及其缓存计数。

在 **Overview** 中，使用 **Compiler jobs** 查找耗时较长的 crate。按 **Duration** 或 **Started after**（自 Cargo 命令启动以来的时间）排序，或按 crate 名称或根源文件搜索。

每一行代表对某个 crate 的一次 `rustc` 调用，该 crate 可能包含多个源文件。**Crate root** 标识其根源文件；持续时间为整个编译器作业的耗时，而非仅该文件的耗时。同一个 crate 可能因不同的目标或配置而出现多次。编译器消息归类在 **Warnings** 和 **Errors** 中。

### 跨构建跟踪 crate {#crate-history}

对于已加入逐步推出的 crate 历史记录功能的项目，**Builds → Crates** 会显示观察到的 crate 及其编译历史。打开一个 crate 以比较其在不同构建中的记录持续时间和结果，然后追溯回对应的 Cargo 构建。相同的项目清单也可通过项目 API 中的 `/cargo/crates` 以及带有 `kind: cargo_crates` 的共享 MCP 构建实体工具获取。

Crate 按其确切记录的根路径、名称和类型分组。更改检出路径可能会分割历史记录；不区分 profile、feature 和目标三元组。这是观察到的编译器作业清单，并非工作区中的每个 crate。已缓存或最新的 crate 不会生成编译样本。

### 归属构建报告 {#report-attribution}

经过身份验证的报告可识别个人凭证背后的个体。共享凭证无需识别个体。你可以选择在报告机器上将 `TUIST_ACTOR_ID` 设置为一个稳定的不透明标识符；默认情况下它处于关闭状态，并显示为未经声明的断言，从不用于授权。较旧的服务器可能会忽略该断言。不要在其中放置密钥。

## 解读时序数据 {#timing-boundaries}

构建持续时间是指整个 Cargo 命令的耗时。编译器作业可以并行运行，因此它们的持续时间之和不一定等于构建持续时间。

Cargo 仅编译需要重新构建的 crate。已经最新的 crate 不会出现在编译器列表中。使用 Tuist 的编译缓存时，恢复的作业会出现在缓存测量中，而不是作为编译器执行记录。

Tuist 不单独测量构建脚本，也不显示构建时间线。大型构建会显示前 500 个编译器作业，如果记录了更多作业则会发出提示。

## 解读缓存测量数据 {#cache-measurements}

`tuist cargo` 包含一个在 Tuist CLI 中实现的实验性编译缓存。请参阅 <.localized_link href="/guides/features/cache/rust">Rust 缓存指南</.localized_link> 了解设置、通过 Kura 进行的远程读写、支持的编译以及故障排除。

在项目侧边栏中打开 **Cargo Cache**，以跟踪跨构建的缓存命中率以及记录的传输、延迟和吞吐量测量数据。按日期或环境过滤，在每日趋势和单次构建命中率之间切换，或打开最近的构建以检查其缓存活动。没有缓存测量数据的构建将显示为不可用，而不是计为零。

打开构建的 **Cache** 选项卡，查看任务命中、任务未命中、命中率以及下载和上传的字节数。当构建报告缓存数据时，该选项卡才会出现。

- **Cacheable Tasks** 显示哪些编译器和构建脚本任务复用了缓存输出。搜索或过滤任务，检查缓存读写延迟，并展开行以查看其输出。
- **CAS Outputs** 显示构件的下载和上传，包括其大小、持续时间和吞吐量。图表统计已完成的传输；已存在的构件和失败的尝试仍保留在表中。

**Hit** 表示复用了缓存输出。**Missed** 表示任务改为进行编译。命中不区分本地和远程；CAS Outputs 显示记录的构件操作。

如果详细记录缺失或不完整，页面会显示提示。摘要仍然涵盖整个构建。估计避免的编译器工作量 **不等于节省的构建 elapsed 时间**。

> [!WARNING] Experimental compilation cache
> 缓存是实验性的，已在 Apple silicon Mac 上验证。库根据编译器读取的源文件进行缓存；构建脚本、过程宏、可执行文件和原生代码仅在 Apple silicon Mac 上缓存。缓存键将检出和工具链路径替换为占位符，因此同一台机器上其他路径的检出可以复用它们。增量编译正常进行。

### 运行测试的构建 {#builds-that-run-tests}

`tuist cargo test` 报告整个命令的持续时间，包括其测试。它还通过 <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link> 报告单个测试结果，包括文档测试。单个测试结果出现在 **Tests** 下；命令持续时间出现在构建洞察中。

## 其他编译器工具 {#other-compiler-tools}

Tuist 保留通过 `RUSTC_WRAPPER`、`CARGO_BUILD_RUSTC_WRAPPER` 或 Cargo 配置设置的现有编译器包装器，并保持 `RUSTC_WORKSPACE_WRAPPER` 不变。预先存在的全局包装器会禁用 Tuist 的缓存和编译器观察器：Tuist 无法确定该包装器是否实际运行了 rustc。自定义工作区包装器同样可能导致报告中显示的编译器作业减少。

Tuist 通过 rustup 查找 Cargo。如果你使用自定义安装，请将 `TUIST_CARGO_EXECUTABLE` 设置为其可执行文件路径。通过直接工具链路径调用 Cargo 会绕过 mise 的包装器。Cargo 别名不能替换诸如 `build` 之类的内置命令。

如果你使用 Cargo 的夜间版 `-C` 选项，请先进入工作区目录：Tuist 会转发 `-C` 命令，但不会收集其构建计时数据。

## 故障排除 {#troubleshooting}

如果构建未出现在仪表板中，请启用调试输出以查看报告未发送的原因：

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

报告功能不会改变构建结果。
