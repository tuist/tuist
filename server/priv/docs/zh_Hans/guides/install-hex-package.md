---
{
  "title": "安装 Hex 包",
  "titleTemplate": ":title · 指南 · Tuist",
  "description": "了解如何在 Elixir 项目中安装和配置 Tuist 的 Hex 包。"
}
---
# 安装 Hex 包 {#install-the-hex-package}

Tuist 提供了一个 [Hex](https://hex.pm/packages/tuist_ex) 包 `tuist_ex`，它可以与你的 Elixir 项目集成，以启用<.localized_link href="/guides/features/build-insights/elixir">构建洞察</.localized_link>和<.localized_link href="/guides/features/test-insights/elixir">测试洞察</.localized_link>等功能。本指南将引导你完成安装和配置过程。

该包需要 Elixir 1.18 或更高版本。它不需要 Tuist 命令行界面。

## 1. 创建项目 {#create-the-project}

在 Tuist 仪表板中创建一个项目，并选择 **Mix (Elixir)** 作为其构建系统。其句柄 `account/project` 用于将你的 Mix 项目与之连接。

## 2. 添加包 {#add-the-package}

将 `tuist_ex` 添加到 `mix.exs` 的依赖项中：

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

然后获取它：

```bash
mix deps.get
```

`runtime: false` 可确保 Tuist 不会包含在你运行的应用程序中。请继续参阅<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">开始使用 Elixir</.localized_link>，以一起配置缓存、构建洞察和测试洞察。以下部分涵盖身份验证和配置详情。

## 3. 为你的团队和持续集成进行身份验证 {#authenticate}

每位团队成员运行以下命令，以便在其机器上访问 Tuist 功能：

```bash
mix tuist.login
```

它会打开浏览器并等待你授权。要在不使用浏览器的情况下登录，请传递你的凭据：

```bash
mix tuist.login --email person@example.com --password secret
```

当你使用自托管或本地 Tuist 服务器时，请在 `mix.exs` 中设置其基础 URL，或者通过 `--url` 传递：

```bash
mix tuist.login --url http://localhost:8080
```

保持主机名拼写一致。例如，为 `localhost` 存储的登录信息与为 `127.0.0.1` 存储的是分开的。

在 GitHub Actions、CircleCI 和 Bitrise 上，持续集成无需登录步骤。任务首次发送报告时，会将提供程序的 OpenID Connect 令牌交换为 Tuist 令牌。<.localized_link href="/guides/integrations/gitforge/github">将你的 GitHub 存储库</.localized_link>连接到你的 Tuist 项目，并在 GitHub Actions 中为该作业授予 `id-token: write` 权限：

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix test
```

对于任何其他 OpenID Connect 身份提供商（例如 Fly.io Machines），请在账户的 **工作负载身份** 部分的 **设置 → 身份验证** 页面中配置工作负载身份信任策略，这将授予 CI 访问该账户拥有的所有当前和未来项目的权限。将 `TUIST_OIDC_ACCOUNT` 设置为拥有该项目的 Tuist 账户，并通过 `TUIST_OIDC_TOKEN` 提供具有策略受众的新颁发身份令牌。当没有账户令牌或有效的存储登录信息时，集成会自动交换它；`mix tuist.login` 也接受在 CI 之外使用它。自动交换仅对同一服务器、账户和提供的身份令牌重用未过期的会话。更改该身份会触发新的交换，而提供空白身份会导致失败，而不是重用早期会话。Tuist 会话在没有刷新令牌的情况下持续一小时，因此对于运行时间较长的工作负载，请在会话过期之前重新颁发身份令牌并再次运行 `mix tuist.login`。请参阅<.localized_link href="/guides/server/authentication#workload-identity-trust-policies">工作负载身份设置</.localized_link>和<.localized_link href="/guides/server/authentication#flyio-machines">Fly.io 示例</.localized_link>。

来自 fork 的拉取请求不会获得 OpenID Connect 令牌，因此它们的运行不会被报告，并且仍然像往常一样通过或失败。在其他提供商处，将 `TUIST_TOKEN` 环境变量设置为账户令牌。按照<.localized_link href="/guides/integrations/continuous-integration#authentication">持续集成身份验证指南</.localized_link>创建一个令牌。

## 4. 继续使用 `mix test` 和 `mix compile` {#aliases}

<.localized_link href="/guides/get-started/elixir-project#set-up-tuist">共享设置</.localized_link>会为你安装编译和测试别名。`mix test test/my_app_test.exs:12 --trace` 会以相同的输出和退出代码报告运行，并且编译集成涵盖由 `mix test` 或 `mix phx.server` 触发的构建。如果编译发现无需执行的操作，则不会报告。

当你直接调用任务名称时，这些任务也能正常工作。Mix 会在 `dev` 环境中以这种方式启动任务，因此该任务必须在第二个进程中为测试环境重新启动。将任务添加到首选环境中以跳过此操作：

```elixir
def cli do
  [preferred_envs: ["tuist.test": :test, "tuist.test.build": :test]]
end
```

## 配置参考 {#configuration-reference}

以下选项可在 `mix.exs` 的项目选项中 `tuist` 下使用：

| 选项 | 类型 | 默认值 | 描述 |
| --- | --- | --- | --- |
| `project` | `String` | 无（必需） | 采用 `account/project` 格式的项目标识符。 |
| `url` | `String` | `"https://tuist.dev"` | Tuist 服务器的基础 URL。 |
| `cache` | `boolean` 或关键字列表 | 禁用 | 设置启用依赖缓存。有关排除项和额外输入，请参阅<.localized_link href="/guides/features/cache/elixir">Elixir 缓存</.localized_link>。 |
| `test_retries` | `integer` | `0` | 重试失败测试的次数；请参阅<.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">测试重试</.localized_link>。 |
| `tags` | `String` 列表 | `[]` | 附加到每个构建的标签；请参阅<.localized_link href="/guides/features/build-insights/elixir#custom-metadata">自定义元数据</.localized_link>。 |
| `values` | 映射 | `%{}` | 附加到每个构建的键值数据。 |

环境变量优先于 `mix.exs`：

| 变量 | 描述 |
| --- | --- |
| `TUIST_PROJECT` | 采用 `account/project` 格式的项目标识符。 |
| `TUIST_URL` | Tuist 服务器的基础 URL。 |
| `TUIST_TOKEN` | 用于身份验证的令牌，替代存储的登录信息。 |
| `TUIST_OIDC_TOKEN` | 新生成的 OpenID Connect 身份令牌，可交换为 Tuist 令牌。对于 GitHub Actions 和 Bitrise，其受众必须为 `tuist`；对于其他提供商，则需匹配项目的信任策略。由 `mix tuist.login` 使用，或在没有账户令牌或有效存储登录信息时作为后备方案。 |
| `TUIST_OIDC_ACCOUNT` | 拥有该项目的 Tuist 账户句柄。通过项目信任策略交换令牌时需要此值。它用于在现有信任策略中进行选择，本身并不授予访问权限。 |
| `TUIST_TEST_RETRIES` | 重试失败测试的次数。 |
| `TUIST_TAGS` | 附加到构建的逗号分隔标签。 |
| `TUIST_VALUES` | 附加到构建的逗号分隔 `key=value` 对。 |
| `TUIST_DEBUG` | 设置为 `1` 以打印报告无法发送的原因。 |

报告永远不会改变 `mix test` 或 `mix compile` 的退出代码。如果无法发送报告，除非设置了 `TUIST_DEBUG=1`，否则任务不会输出任何信息。

## 后续步骤 {#next-steps}

安装并配置包后，你可以使用：

- <.localized_link href="/guides/features/cache/elixir">依赖缓存</.localized_link>，以便在本地和 CI 构建中重用已编译的依赖项。
- <.localized_link href="/guides/features/build-insights/elixir">构建洞察</.localized_link>，用于跟踪编译时间、警告以及阻碍构建的因素。
- <.localized_link href="/guides/features/test-insights/elixir">测试洞察</.localized_link>，用于跟踪每个测试的性能。
- <.localized_link href="/guides/features/test-insights/flaky-tests/elixir">不稳定测试</.localized_link>，用于检测和跟踪间歇性失败的测试。
- <.localized_link href="/guides/features/test-sharding/elixir">测试分片</.localized_link>，以便在持续集成运行器上分布你的测试。
