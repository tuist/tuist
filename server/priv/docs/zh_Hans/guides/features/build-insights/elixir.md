---
{
  "title": "Elixir 构建洞察",
  "titleTemplate": ":title · 构建洞察 · 功能 · 指南 · Tuist",
  "description": "追踪你的 Elixir 项目使用 Mix 编译所需的时间、警告信息，以及拖慢构建速度的文件。"
}
---
# Elixir 构建洞察 {#elixir-build-insights}

Tuist 的 Hex 包可以将构建分析数据发送到 Tuist。构建耗时、文件之间的依赖关系图，以及这两者随时间的演变，为你提供了优化构建图并充分利用编译环境中所有可用核心所需的信息。

> [!IMPORTANT] REQUIREMENTS
> - 完成<.localized_link href="/guides/get-started/elixir-project">开始使用 Elixir</.localized_link>

## 报告你的构建 {#report-your-builds}

共享设置会安装编译集成。继续使用你常用的命令：

```bash
mix compile
```

该集成涵盖 `mix compile` 以及由其他任务触发的每次编译，例如 `mix test` 或 `mix phx.server`。如果编译发现无需执行任何操作，则不会上报，因此仪表板仅列出实际执行了工作的构建。

## 报告参与者声明 {#report-actor-claim}

Mix 构建和测试报告请求仅在你显式配置标签时才包含可选的 `x-tuist-actor-id` 标头。将 `TUIST_ACTOR_ID` 设置为组织范围内的标签，或在项目的 `tuist` 配置中添加 `actor_id: "developer-label"`。解析时优先使用环境变量，其次是运行时 `:actor_id` 选项，最后是项目配置。默认情况下不发送任何标签，且该包不会检测操作系统用户名。固定的项目标签适用于使用该配置的每个人。空值或无效的覆盖会省略声明而不是回退；这不会移除基于凭据的已验证身份。如果自定义代理拒绝陌生的标头，请使用 `TUIST_ACTOR_ID=""` 选择退出。

标识符必须是 1–128 字节的非空格可打印 ASCII 字符。无效的覆盖会被省略而不回退。已验证的个人凭据具有优先权；其他客户端报告的标识符显示为 **未验证**，从不授权访问，也从不自动链接到用户。任何可以查看项目报告的人都能看到这些标识符，包括项目公开时的公众查看者，并且它们包含在数据导出中，因此不要包含秘密信息。旧服务器会忽略此可选标头，而新服务器接受不带此标头的旧客户端。没有标识符的新共享令牌报告显示 **未知**，而不是发布组织；历史报告保留其先前的归属。默认情况下，构建和测试报告需要身份验证。自托管安装可以按照下文所述显式启用无凭据报告。

## 私有网络上的无凭据报告 {#network-trusted-publishing}

操作员在实例上配置 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` 并按照 <.localized_link href="/guides/server/self-host/server#network-trusted-access">自托管指南</.localized_link> 中的描述重启实例后，配置你的目标地址。当缺少凭据时，SDK 会自动发现实例是否允许无凭据报告。实例设置涵盖每个支持的项目，且仪表板上没有切换开关：

```elixir
tuist: [
  url: "https://tuist.internal.example",
  project: "account/project"
]
```

`mix tuist.compile` 和 `mix tuist.test` 在确实缺少凭据且发现机制确认服务器允许的情况下，无需登录即可发布结构化报告。不需要客户端标志或项目加入。现有的凭据（包括提供的 CI OIDC 身份）会被使用或拒绝，绝不会因忽略而降级为无签名报告。仅包含空白的 `TUIST_TOKEN` 会导致错误。空的 `TUIST_TOKEN` 可以回退到有效的存储凭据或提供的 OIDC，过期的存储凭据也可以回退到提供的 OIDC；这两种路径都保持身份验证状态，绝不会启用无签名报告。不可用的凭据会被保留，并在没有成功的身份验证回退时失败。在升级无凭据客户端之前，先将每个服务器副本升级到支持发现的版本；不支持发现的旧服务器、禁用的实例以及发现失败的情况仍然需要身份验证。

无签名运行属于遥测数据，而非受信任的不稳定测试、隔离、覆盖率或选择性执行证据。分片规划、构建归档以及覆盖率/制品端点仍然需要凭据。独立设置 `TUIST_ACTOR_ID=""` 以省略配置的参与者声明；已验证的凭据身份不受影响。

## 跟踪内容 {#what-is-tracked}

对于每次构建，该包会收集：
- 其持续时间、是否成功，以及运行时的 Elixir、Erlang/OTP 和 Mix 环境
- 每个警告和错误，及其所在的文件和行号
- 每个文件的编译耗时，以及它定义的模块
- 每个文件所依赖的文件，以及是在编译时还是仅在运行时需要它们
- 除了编译文件之外构建执行的操作，例如类型检查、写入磁盘以及其他 Mix 编译器
- 构建期间机器的处理器、内存、网络和磁盘使用情况
- 分支和提交，以及在持续集成中，提供者和运行

## 找出导致构建变慢的原因 {#find-what-slows-a-build-down}

在仪表板上从 **构建 → 构建运行** 打开一个构建。构建、它们的诊断计数以及依赖缓存摘要也可以通过 `tuist build mix list` 和 `tuist build mix show`、`GET /api/projects/{account_handle}/{project_handle}/mix/builds`，以及 `list_mix_builds` 和 `get_mix_build` <.localized_link href="/guides/features/agentic-coding/mcp">MCP 工具</.localized_link> 获取。

**概览** 选项卡列出了构建编译的文件。你可以按模块对它们进行分组、搜索，并按以下方式排序：
- **编译持续时间**，用于查找本身较慢的文件。
- **编译时依赖者**，即在该文件编译完成之前无法编译的文件数量。拥有许多依赖者的慢速文件会阻碍构建的其余部分，更改它会重新编译所有这些文件。
- **编译时依赖项**，即该文件等待的文件数量。

![Phoenix 应用程序的 Mix 构建概览](/images/guides/features/elixir/build.png)

**时间线** 选项卡显示了同一构建随时间的变化：哪些文件并行编译、构建在何处进行类型检查和写入磁盘，以及机器在每个时刻的状态。只有一根条形图的时段表示构建无法利用其拥有的核心。

![Phoenix 应用程序完整 Mix 构建的时间线](/images/guides/features/elixir/build-timeline.png)

**警告** 和 **错误** 选项卡列出了构建的诊断信息。

## 自定义元数据 {#custom-metadata}

将标签和键值数据附加到 Mix 构建，以区分来自不同团队、硬件或工作流的运行。两者都会出现在每个构建的详情页面中。

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

两处的标签会合并。当同一键在两处都配置时，环境变量中的值优先。

标签只能包含字母、数字、连字符和下划线。一个构建最多可以有 50 个标签，每个标签最多 50 个字符。一个构建最多可以有 20 个键值条目，每个键最多 50 个字符，每个值最多 500 个字符。这些与 Xcode 构建元数据使用的服务器端限制相同。包在发送报告之前会跳过无效标签以及过大或空的元数据条目，因此无效配置不会阻止其余构建洞察报告的存储。对于不符合标签约束的值，请使用键值元数据。

自定义元数据附加到构建，而不是测试运行。

项目成员可以在仪表板上查看自定义元数据。不要将其用于凭据、访问令牌或其他敏感数据。Tuist 保留 Mix 构建数据（包括此元数据）90 天。详见<.localized_link href="/guides/server/data-retention">数据保留政策</.localized_link>。

## 故障排除 {#troubleshooting}

报告永远不会改变构建的结果：如果无法发送报告，构建将照常完成，且不会打印任何内容。要查看报告未发送的原因，请设置 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix compile --force
```
