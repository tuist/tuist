---
{
  "title": "Elixir Build Insights",
  "titleTemplate": ":title · Build Insights · Features · Guides · Tuist",
  "description": "Track how long your Elixir project takes to compile with Mix, its warnings, and the files that hold your builds back."
}
---
# Elixir 构建洞察 {#elixir-build-insights}

Tuist 的 Hex 包可以将构建分析数据发送到 Tuist。构建耗时、文件之间的依赖关系图，以及这两者随时间的演变，为你提供了优化构建图并充分利用编译环境中所有可用核心所需的信息。

> [!IMPORTANT] REQUIREMENTS
> - 完成 <.localized_link href="/guides/get-started/elixir-project">Elixir 入门指南</.localized_link>

## 报告你的构建 {#report-your-builds}

共享设置会安装编译集成。请继续使用你常用的命令：

```bash
mix compile
```

该集成涵盖 `mix compile` 以及由其他任务触发的每次编译，例如 `mix test` 或 `mix phx.server`。如果编译发现无需执行任何操作，则不会上报，因此仪表板仅列出实际执行了工作的构建。

## 报告 Actor 声明 {#report-actor-claim}

Mix 构建和测试报告请求仅在你显式配置标签时才包含可选的 `x-tuist-actor-id` 标头。将 `TUIST_ACTOR_ID` 设置为组织范围的标签，或在项目的 `tuist` 配置中添加 `actor_id: "developer-label"`。解析优先使用环境变量，其次是运行时 `:actor_id` 选项，最后是项目配置。默认情况下不发送任何标签，且该包不会检测操作系统用户名。固定的项目标签适用于使用该配置的每个人。空值或无效的覆盖将省略声明而不是回退；这不会移除基于凭据的已验证身份。如果自定义代理拒绝陌生的标头，请使用 `TUIST_ACTOR_ID=""` 选择退出。

标识符必须是 1–128 字节的非空格可打印 ASCII 字符。无效的覆盖将被省略且不回退。已验证的个人凭据具有优先权；其他客户端报告的标识符显示为 **未验证**，绝不会授权访问，也绝不会自动链接到用户。任何能够查看项目报告的人都可以看到这些标识符，包括项目公开时的公共查看者，并且它们包含在数据导出中，因此请勿包含机密信息。旧服务器会忽略可选标头，而新服务器接受不带该标头的旧客户端。没有标识符的新共享令牌报告显示 **未知**，而不是发布组织；历史报告保留其先前的归属。默认情况下，构建和测试报告需要身份验证。自托管安装可以按照下文所述显式启用无凭据报告。

## 在私有网络上进行无凭据报告 {#network-trusted-publishing}

操作员在实例上配置 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` 并按照 <.localized_link href="/guides/server/self-host/server#network-trusted-access">自托管指南</.localized_link> 中的描述重启后，配置你的目标地址。当缺少凭据时，SDK 会自动发现实例是否允许无凭据报告。实例设置涵盖每个受支持的项目，且仪表板上没有切换开关：

```elixir
tuist: [
  url: "https://tuist.internal.example",
  project: "account/project"
]
```

`mix tuist.compile` 和 `mix tuist.test` 在确实缺少凭据且发现确认服务器允许的情况下，无需登录即可发布结构化报告。不需要客户端标志或项目选择加入。现有的凭据（包括提供的 CI OIDC 身份）会被使用或拒绝，绝不会被忽略以降級为无签名报告。仅包含空白字符的 `TUIST_TOKEN` 是错误的。空的 `TUIST_TOKEN` 可以回退到有效的存储凭据或提供的 OIDC，而过期的存储凭据也可以回退到提供的 OIDC；这两种路径都保持身份验证状态，绝不会启用无签名报告。不可用的凭据会被保留，并在没有成功的身份验证回退时失败。在升级无凭据客户端之前，请将每个服务器副本升级到支持发现的版本；不支持发现的旧服务器、禁用的实例以及发现失败仍然需要身份验证。

无签名运行属于遥测数据，而非受信任的不稳定性、隔离、覆盖率或选择性执行证据。分片规划、构建归档以及覆盖率/工件端点仍然需要凭据。独立设置 `TUIST_ACTOR_ID=""` 以省略配置的 actor 声明；已验证的凭据身份不受影响。

## 跟踪内容 {#what-is-tracked}

对于每次构建，该包会收集：
- 其持续时间、是否成功，以及运行时的 Elixir、Erlang/OTP 和 Mix 环境
- 每个警告和错误，及其所在的文件和行号
- 每个文件的编译耗时，以及它定义的模块
- 每个文件依赖的文件，以及是在编译时还是仅在运行时需要它们
- 除了编译文件之外构建执行的操作，例如类型检查、写入磁盘以及其他 Mix 编译器
- 构建期间机器的处理器、内存、网络和磁盘使用情况
- 分支和提交，以及在持续集成中的提供者和运行

## 查找导致构建变慢的原因 {#find-what-slows-a-build-down}

在仪表板上从 **构建 → 构建运行** 打开一个构建。构建、其诊断计数及其依赖缓存摘要也可以通过 `tuist build mix list` 和 `tuist build mix show`、`GET /api/projects/{account_handle}/{project_handle}/mix/builds` 以及 `list_mix_builds` 和 `get_mix_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link> 获取。

**概览** 选项卡列出了构建编译的文件。你可以按模块对它们进行分组、搜索，并按以下方式排序：
- **编译持续时间**，用于查找本身较慢的文件。
- **编译时依赖者**，即在此文件编译完成之前无法编译的文件数量。拥有许多依赖者的慢速文件会阻碍其余构建的进行，更改它会重新编译所有这些文件。
- **编译时依赖项**，即此文件等待的文件数量。

![Phoenix 应用程序的 Mix 构建概览](/images/guides/features/elixir/build.png)

**时间线** 选项卡显示了同一构建随时间的变化：哪些文件并行编译、构建在哪里进行类型检查和写入磁盘，以及机器在每个时刻的状态。只有一个条形图的区间表示构建无法利用其拥有的核心。

![Phoenix 应用程序完整 Mix 构建的时间线](/images/guides/features/elixir/build-timeline.png)

**警告** 和 **错误** 选项卡列出了构建的诊断信息。

## 自定义元数据 {#custom-metadata}

将标签和键值数据附加到 Mix 构建，以区分来自不同团队、硬件或工作流的运行。两者都会出现在每个构建的详细信息页面上。

使用环境变量设置元数据：

```sh
export TUIST_TAGS="nightly,release"
export TUIST_VALUES="ticket=TUIST-123,runner=linux-arm64"
```

你也可以在 `mix.exs` 中配置元数据：

```elixir
tuist: [
  project: "account/project",
  tags: ["nightly", "release"],
  values: %{"ticket" => "TUIST-123", "runner" => "linux-arm64"}
]
```

来自两处的标签会合并。当同一键在两处都配置时，环境变量中的值优先。

标签只能包含字母、数字、连字符和下划线。一个构建最多可以有 50 个标签，每个标签最多可以包含 50 个字符。一个构建最多可以有 20 个键值条目，每个键最多可以包含 50 个字符，每个值最多可以包含 500 个字符。这些与用于 Xcode 构建元数据的服务器端限制相同。包在发送报告之前会跳过无效标签以及过大或空的元数据条目，因此无效配置不会阻止其余构建洞察报告的存储。对于不符合标签约束的值，请使用键值元数据。

自定义元数据附加到构建，而不是测试运行。

自定义元数据对仪表板中的项目成员可见。不要将其用于凭据、访问令牌或其他敏感数据。Tuist 保留 Mix 构建数据（包括此元数据）90 天。有关详细信息，请参阅 <.localized_link href="/guides/server/data-retention">数据保留政策</.localized_link>。

## 故障排除 {#troubleshooting}

报告永远不会改变构建的结果：如果无法发送报告，构建将照常完成，且不会打印任何内容。要查看未发送报告的原因，请设置 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix compile --force
```
