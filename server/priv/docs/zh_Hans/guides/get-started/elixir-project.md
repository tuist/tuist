---
{
  "title": "Elixir 项目",
  "titleTemplate": ":title · 入门指南 · 教程 · Tuist",
  "description": "为 Elixir 配置一次 Tuist，即可实现依赖缓存、构建与测试洞察、不稳定测试检测以及可选的测试分片。"
}
---
# Elixir 项目 {#elixir-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/elixir-project
```

:::

一次性设置 Tuist，然后继续使用 `mix compile` 和 `mix test`。`tuist_ex` Hex 包会缓存受支持的依赖项，并将构建和测试运行报告到你的仪表板。

## 前提条件

- 一个使用 Mix 构建的 Elixir 项目，基于 Elixir 1.18 或更高版本。
- 一个 Tuist 账户。

## 设置 Tuist {#set-up-tuist}

在 Tuist 仪表板中创建一个项目，并选择 **Mix (Elixir)** 作为其构建系统。将该包添加到你的 `mix.exs` 中的依赖项：

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

获取它，配置你的项目，并登录：

```bash
mix deps.get
mix tuist.setup --project account/project
mix tuist.login
```

设置过程会用你的项目句柄更新 `mix.exs`，启用依赖项缓存，并安装编译和测试别名。它会保留其他设置和标准测试准备步骤，例如 Phoenix 的数据库设置。如果无法安全地集成自定义别名，它将停止操作且不更改文件。

提交更新后的 `mix.exs`，以便你的团队和 CI 使用相同的设置。无需复制任何脚本或求值代码。登录会打开浏览器；有关无头登录和 CI 凭据，请参阅 <.localized_link href="/guides/install-hex-package#authenticate">authentication</.localized_link>。

现在运行你常用的命令：

```bash
mix compile
mix test
```

构建会显示在 **Builds** 下，测试运行显示在 **Tests** 下，依赖项缓存活动显示在 **Mix cache** 下。这是三者共享的设置。不稳定测试检测使用报告的运行数据；重试和 CI 分片是可选的。

## 依赖项缓存

Tuist 会自动选择受支持的 Hex 和 Git 依赖项，无需依赖项列表。缓存未命中时会正常编译并保存结果；缓存命中时会恢复结果。原生/自定义编译和本地依赖项仍由 Mix 处理。

编译必须是可复现的：声明额外的编译时输入，并排除具有未建模输入或必需副作用的依赖项。有关受支持的输入、缓存验证和自定义，请参阅 <.localized_link href="/guides/features/cache/elixir">Elixir cache</.localized_link>。

## 构建洞察

构建时间、文件之间的依赖关系图以及两者随时间的演变，为你提供了优化构建图并充分利用编译环境中所有核心所需的信息。

有了 `compile` 别名，Tuist 会报告每次构建：耗时、警告和错误、每个文件的编译耗时以及它所依赖的文件。在下一次 `mix compile` 之后，打开仪表板上的 **Builds** 即可查看。

## 测试洞察

Tuist 会记录每次 `mix test` 运行中每个测试的结果和持续时间，因此你可以查看测试套件随时间的演变，找出缓慢或变慢的测试，并理解为什么某次运行在 CI 中失败。你可以在仪表板的 **Tests** 下找到它们，详细到模块、`describe` 块和具体测试。

## 不稳定测试

不稳定测试在使用相同代码时会时而通过时而失败。当某个测试在 CI 的同一提交上既失败又通过时，Tuist 会将其标记为不稳定。你还可以让包重试失败的测试，从而在一次运行中检测到它们：

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

重试后通过的测试会被报告为不稳定，且该次运行视为成功。**Flaky Tests** 页面会列出这些测试。

## 测试分片

测试分片将你的测试套件分布到多个 CI 运行器上。Tuist 根据之前运行中每个测试文件的耗时来平衡分片，并且只编译一次项目，然后将该构建共享给每个运行器。一条命令即可规划分片：

```bash
mix tuist.test.build --shard-max 4
```

然后，每个运行器在设置 `TUIST_SHARD_INDEX` 的情况下运行其分片，结果会作为单次测试运行出现在仪表板上：

```bash
TUIST_SHARD_INDEX=0 mix test
```

## 让团队加入

洞察的价值会随着连接到项目的人数增加而累积。从仪表板的账户设置中邀请你的队友加入组织，并设置 <.localized_link href="/guides/integrations/authentication/sso">Single Sign-On</.localized_link>（Google、Okta、Microsoft），这样入职只需点击一下，而无需每人执行 `mix tuist.login`。

对于 CI，不要使用个人登录。GitHub Actions、CircleCI 和 Bitrise 可以通过 OpenID Connect 进行身份验证；在其他提供商上，设置一个具有适当范围的 `TUIST_TOKEN`。请遵循 <.localized_link href="/guides/install-hex-package#authenticate">CI authentication steps</.localized_link>。
