---
{
  "title": "Rust 构建洞察",
  "titleTemplate": ":title · 构建洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 中查找耗时较长的 crate，比较构建性能，并检查 Rust 编译器警告和错误。"
}
---
# Rust 构建洞察 {#rust-build-insights}

构建洞察帮助你找出拖慢 Cargo 构建的因素，并在回归问题影响整个团队之前将其捕获。你可以将本地构建与 CI 构建进行对比，查看构建时间的变化，并检查每次构建中编译的 crate。

> [!IMPORTANT] Requirements
> - 按照<.localized_link href="/guides/get-started/rust-project">Rust 项目设置</.localized_link>连接你的项目并完成身份验证。

## 上报你的构建 {#report-your-builds}

通过 Tuist 运行你常用的 Cargo 命令：

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo +nightly build --features tracing
```

如果你使用 mise，<.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">配置 Cargo 包装器</.localized_link>以继续使用普通的 `cargo` 命令。你的参数、工具链选择、输出和退出码保持不变。

## 找出拖慢构建的因素 {#explore-your-builds}

在仪表板的**构建 → 构建运行**中打开一个构建。使用日期、环境和 Rust 版本过滤器来对比相似的构建。构建及其缓存计数也可以通过 `tuist build cargo list` 和 `tuist build cargo show`、`GET /api/projects/{account_handle}/{project_handle}/cargo/builds`，以及 `list_cargo_builds` 和 `get_cargo_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link>获取。

在**概览**中，使用**编译器作业**查找耗时较长的 crate。按**持续时间**或**开始于**（自 Cargo 命令启动以来的时间）排序，或按 crate 名称或根源文件搜索。

每一行代表对一个 crate 的一次 `rustc` 调用，该 crate 可能包含多个源文件。**Crate 根目录**标识其根源文件；持续时间是针对整个编译器作业的，而非仅针对该文件。同一个 crate 可能因不同的目标或配置而出现多次。编译器消息归类在**警告**和**错误**中。

## 解读计时数据 {#timing-boundaries}

构建持续时间是指整个 Cargo 命令所花费的时间。编译器作业可以并行运行，因此它们的持续时间之和不会等于构建持续时间。

Cargo 仅编译需要重新构建的 crate。已经最新的 crate 不会出现在编译器列表中。借助 Tuist 的编译缓存，恢复的作业会显示在缓存测量数据中，而不是作为编译器执行记录。

Tuist 不会单独测量构建脚本，也不会显示构建时间线。大型构建会显示前 500 个编译器作业，如果记录了更多作业，则会显示提示。

## 解读缓存测量数据 {#cache-measurements}

`tuist cargo` 包含一个在 Tuist CLI 中实现的实验性编译缓存。请遵循<.localized_link href="/guides/features/cache/rust">Rust 缓存指南</.localized_link>进行设置、了解通过 Kura 进行的远程读写、支持的编译类型以及故障排除方法。

在项目侧边栏中打开**Cargo 缓存**，以跟踪跨构建的缓存命中率以及记录的传输、延迟和吞吐量测量数据。按日期或环境过滤，在每日趋势和单次构建命中率之间切换，或打开最近的构建以检查其缓存活动。没有缓存测量数据的构建将保持不可用状态，而不会被计为零。

打开构建的**缓存**标签页，查看任务命中、任务未命中、命中率以及下载和上传的字节数。当构建报告缓存数据时，该标签页才会显示。

- **可缓存任务**显示哪些编译器和构建脚本任务复用了缓存输出。搜索或过滤任务，检查缓存读/写延迟，并展开行以查看其输出。
- **CAS 输出**显示构件的下载和上传情况，包括其大小、持续时间和吞吐量。图表统计已完成的传输；已存在的构件和失败的尝试仍保留在表格中。

**命中**表示复用了缓存输出。**未命中**表示任务进行了编译。命中不区分本地和远程；CAS 输出显示记录的构件操作。

如果详细记录缺失或不完整，页面会显示提示。摘要仍然涵盖整个构建。估计避免的编译器工作量**并非节省的构建耗时**。

> [!WARNING] Experimental compilation cache
> 首个版本仅缓存具有已验证输入和输出的注册表叶级库。工作区 crate、构建脚本、过程宏、对其他 crate 的依赖、增量编译、原生链接和可执行文件均正常构建。缓存键保留绝对路径，因此尚不支持在不同检出路径之间复用。

### 运行测试的构建 {#builds-that-run-tests}

`tuist cargo test` 报告整个命令的持续时间，包括其测试。它还通过<.localized_link href="/guides/features/test-insights/rust">Rust 测试洞察</.localized_link>报告单个测试结果，包括文档测试。单个测试结果出现在**测试**下；命令持续时间出现在构建洞察中。

## 其他编译器工具 {#other-compiler-tools}

Tuist 保留通过 `RUSTC_WRAPPER`、`CARGO_BUILD_RUSTC_WRAPPER` 或 Cargo 配置设置的现有编译器包装器，并保持 `RUSTC_WORKSPACE_WRAPPER` 不变。预先存在的全局包装器会禁用 Tuist 的缓存和编译器观察器：Tuist 无法确定该包装器是否实际运行了 rustc。自定义工作区包装器同样可能导致报告中显示的编译器作业减少。

Tuist 通过 rustup 查找 Cargo。如果你使用自定义安装，请将 `TUIST_CARGO_EXECUTABLE` 设置为其可执行文件路径。通过直接工具链路径调用 Cargo 会绕过 mise 的包装器。Cargo 别名无法替换诸如 `build` 之类的内置命令。

如果你使用 Cargo 的夜间版 `-C` 选项，请改为先切换到工作区目录：Tuist 会转发 `-C` 命令，但不会收集其构建计时数据。

## 故障排除 {#troubleshooting}

如果构建未出现在仪表板中，请启用调试输出以查看其报告未发送的原因：

```sh
TUIST_DEBUG=1 tuist cargo build --workspace
```

报告不会改变你的构建结果。
