---
title: Elixir 缓存
titleTemplate: ":title · 缓存 · 指南 · Tuist"
description: 为你的 Elixir 项目启用依赖缓存，并继续使用 Mix。
---

# Elixir 缓存

Tuist 会在本地和 CI 构建中复用已编译的依赖。只需启用一次，然后继续使用 `mix compile` 和 `mix test`。

## 设置

按照<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">开始使用 Elixir</.localized_link>指南操作一次。共享设置可在提供构建和测试洞察的同时启用依赖缓存；无需额外的缓存配置。

`cache: true` 会自动选择受支持的 Hex 和 Git 依赖；你无需列出它们。原生/自定义编译和本地依赖仍通过 Mix 正常进行。你的应用程序源文件不会被缓存。

## 照常构建

```sh
mix compile
mix test
```

当某个依赖需要编译时，Tuist 会先检查本地缓存，再检查共享的远程缓存。未命中时会正常编译并将结果存储以供后续构建使用。对于 Mix 认为已是最新的选定且受支持的依赖，如果其编译产物存在且有效，则计为本地命中；无需查询缓存。如果身份验证或缓存不可用，Mix 仍会正常编译。

## 查看缓存命中情况

在项目仪表板中打开**Mix Cache**，查看命中率、传输量和最近的构建。选择某个构建的**Mix cache**标签页，查看哪些任务命中或未命中。**CAS Outputs**显示实际的远程下载和上传；本地命中不会创建远程传输记录。复用已最新的产物会计入命中率，但不会产生传输字节数、恢复延迟或预估节省的时间。

要尝试恢复，请清理某个受支持依赖的编译产物并重新构建：

```sh
mix deps.clean nimble_options --build
mix compile
```

将 `nimble_options` 替换为你的项目中已填充缓存的依赖。保持相同的 Mix 环境和编译器设置。

## 仅在需要时自定义

大多数项目可以保留 `cache: true`。如有例外，请使用关键字列表：

```elixir
tuist: [
  project: "your-account/your-project",
  cache: [exclude: [:a_dependency_with_compile_time_side_effects]]
]
```

- **额外的编译时输入：** 使用 `inputs: ["schemas"]` 声明外部文件，使用 `env: ["COMPILER_OPTION"]` 声明环境变量。
- **仅限本地：** 设置为 `remote: false`。
- **不上传到远程：** 设置为 `upload: false`。服务器权限仍然控制访问。
- **禁用缓存：** 设置为 `cache: false`。

> [!IMPORTANT]
> 编译可以执行任意 Elixir 代码。请声明额外的输入，并排除那些包含时间/网络相关代码或副作用、必须在每次构建中运行的依赖。缓存制品可能包含密钥，而缓存写入者是受信任的代码生产者：不要给不受信任的作业授予缓存写入凭证。

有关依赖选择、在不同检出路径间复用、故障排查和实现细节，请参阅<.localized_link href="/guides/features/cache/elixir-advanced">高级 Elixir 缓存配置</.localized_link>。
