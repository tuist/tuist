---
{
  "title": "Rust 缓存",
  "titleTemplate": ":title · 缓存 · 功能 · 指南 · Tuist",
  "description": "通过 Cargo 在本地和 Tuist 远程缓存中复用受支持的 Rust 编译产物。"
}
---
# Rust 缓存 {#rust-cache}

Tuist 会缓存受支持的 Rust 编译输出，以便在 Cargo 的构建输出被移除后重用它们。该缓存内置于 Tuist CLI 中。无需安装单独的缓存可执行文件或 Cargo 插件。

> [!WARNING] Experimental compilation cache
> 当前版本仅缓存注册表叶库：从 Cargo 注册表下载且不依赖其他 crate 的库 crate。其他编译正常进行。缓存键保留绝对路径和环境输入，因此尚不支持在不同检出位置之间重用。

## 启用缓存 {#enable-caching}

按照<.localized_link href="/guides/get-started/rust-project">Rust 项目设置</.localized_link>连接你的项目并进行身份验证。然后通过 Tuist 运行构建：

```sh
tuist cargo build --release
```

符合条件的编译会自动缓存。无需额外的缓存配置或启用标志。Tuist 会根据你现有的项目和服务器配置发现账户的缓存端点并获取缓存凭据。

如果你使用 mise，请<.localized_link href="/guides/get-started/rust-project#keep-typing-cargo">配置 Cargo 包装器</.localized_link>以继续输入普通的 `cargo` 命令。

## 工作原理 {#how-it-works}

对于每个符合条件的编译，Tuist 会：

1. 检查本地缓存中是否有匹配的输出。
2. 如果本地未命中，则通过远程执行 API (REAPI) 查询 Kura，下载任何缺失的内容，并在恢复之前验证输出。
3. 如果缓存未命中，则正常运行编译器。编译成功后，它会将输出存储在本地，并在获得授权时通过 REAPI 上传到 Kura。只有在其所有引用的内容都可用后，才会发布远程缓存条目。

本地和 CI 构建使用相同的远程缓存协议。读写访问权限来自 Tuist 服务器颁发的缓存凭据和你账户的<.localized_link href="/guides/features/cache#restrict-uploads-to-ci">缓存上传策略</.localized_link>。账户可以允许开发者下载，同时将上传限制为 CI 和账户令牌。缓存写入者是受信任的代码生产者：缓存的编译器输出是可执行代码，因此只向你信任的机器和令牌授予写入权限。

如果远程设置失败，本地缓存仍然可用。不可用、缺失或损坏的缓存条目会回退到编译。上传失败不会导致构建失败，也不会丢弃其本地缓存条目。

## 哪些内容可以被缓存 {#what-can-be-cached}

当前缓存支持符合条件的注册表叶库，这些库生成 Rust 库工件及其附带的元数据、依赖信息和支持的拆分调试输出。

以下内容仍正常构建：

- 工作区 crate 和依赖其他 crate 的库。
- 构建脚本、过程宏以及依赖其输出的 crate。
- 可执行文件、测试二进制文件、原生链接和 C/C++ 编译。
- 增量编译、自定义目标以及不受支持的编译器参数或源输入。
- 仅元数据的 `cargo check` 调用。
- 发出渲染诊断信息或意外编译器输出的编译。

预先存在的全局编译器包装器会禁用 Tuist 的编译缓存和编译器观察器。自定义工作区包装器也会绕过缓存。请参阅<.localized_link href="/guides/features/build-insights/rust#other-compiler-tools">编译器工具兼容性</.localized_link>。

缓存键包括包内容、编译器和工具链、参数、工作目录和构建环境。凭据、Tuist 报告设置和已识别的 CI 运行元数据不会使条目失效。在编译期间读取这些排除变量的 crate 不会被缓存。在测试重用时，保持其他输入及其绝对路径一致。远程传输支持并不会使输出在不同的检出路径之间可重定位。

## 验证重用 {#verify-reuse}

Cargo 已经避免重新构建最新的输出。为了测试 Tuist 的缓存而不是 Cargo 的现有输出，请构建一次，移除 Cargo 的输出，然后重复相同的构建：

```sh
tuist cargo build --release
cargo clean
tuist cargo build --release
```

符合条件的库可以在第二次构建时恢复；不支持的 crate 仍会编译。移除 Cargo 的输出不会移除 Tuist 独立的本地缓存。这检查的是重用，不一定是远程下载：本地命中不需要从 Kura 传输。输入验证和缓存操作会增加开销，因此避免编译并不能保证小型 crate 的构建更快。

## 检查缓存活动 {#inspect-cache-activity}

在项目仪表板中打开**Cargo 缓存**以检查命中率、记录的传输、延迟、吞吐量和最近的构建。打开构建的**缓存**选项卡以查看单个任务决策和 CAS 输出。

缺失的测量值不计为零，缓存命中也不一定意味着远程下载。详见<.localized_link href="/guides/features/build-insights/rust#cache-measurements">Rust 缓存测量</.localized_link>。

## 故障排除 {#troubleshooting}

启用调试输出以检查缓存传输和报告失败：

```sh
TUIST_DEBUG=1 tuist cargo build --release
```

如果没有看到命中，请检查你的构建是否包含符合条件的注册表叶库，是否有其他编译器包装器优先，以及编译器、标志、环境和路径是否与填充缓存的构建匹配。对于远程上传，还要检查身份验证和账户的缓存上传政策。
