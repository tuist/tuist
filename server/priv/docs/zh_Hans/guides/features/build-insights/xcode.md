---
{
  "title": "Xcode 构建洞察",
  "titleTemplate": ":title · 构建洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 仪表板中跟踪 Xcode 构建分析数据，以监控本地和 CI 构建性能。"
}
---
# Xcode 构建洞察 {#xcode-build-insights}

在大型项目上工作不应要求反复重新构建相同的代码。Tuist Build Insights 让你跟踪构建分析，以便在本地和 CI 构建时间成为瓶颈之前识别趋势。

构建洞察由 `tuist inspect build` 命令驱动，该命令通常添加到你的 scheme 的 post-action 中。

要开始跟踪本地构建时间，你可以利用 `tuist inspect build` 命令，将其添加到你的 scheme 的 post-action 中：

![用于检查构建的 Post-action](/images/guides/features/build-insights/inspect-build-scheme-post-action.png)

> [!NOTE]
> 将“Provide build settings from”字段设置为可执行文件或你的主要构建目标，以捕获构建配置。


> [!NOTE]
> 当构建失败时，不会执行 post-scheme action。

>
> 在这种情况下，你可以通过在相关的 `project.pbxproj` `BuildAction` 中将 `runPostActionsOnFailure` 设置为 `YES` 来执行它：
>
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

对于 [Mise](https://mise.jdx.dev/)，在 post-action 环境中激活 `tuist`：

```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

> [!TIP]
> **Mise 路径解析**
>
> 你的环境的 `PATH` 不会被 scheme post action 继承，因此请使用 Mise 的绝对路径。这取决于你如何安装 Mise。构建设置应从目标继承，以便 `mise` 可以从 `$SRCROOT` 运行。

对于 [Homebrew](https://brew.sh/)，将 Homebrew 路径添加到 post-action 环境中：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
tuist inspect build
```

Actor claim 默认处于禁用状态。要为 scheme post-action 配置一个，请在该脚本中设置 `TUIST_ACTOR_ID`，而不是依赖 shell 导出。从 Dock 启动的 Xcode 不会继承来自 `~/.zshrc` 的变量。要使用 Homebrew 显式抑制已配置的 claim，请使用：

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export TUIST_ACTOR_ID=""
tuist inspect build
```

使用 Mise 时，在 Mise 加载其环境后覆盖该值：

```sh
$HOME/.local/bin/mise x -C "$SRCROOT" -- env TUIST_ACTOR_ID="" tuist inspect build
```

使用显式标签而不是空值来选择加入。

登录后，本地构建将被跟踪并可在 Tuist 仪表板中查看：

> [!TIP]
> 要快速访问仪表板，请从 CLI 运行 `tuist project show --web`。


![带有构建洞察的仪表板](/images/guides/features/build-insights/builds-dashboard.png)

## CI 中的构建洞察 {#continuous-integration}

要在 CI 上跟踪构建洞察，请确保 CI 已<.localized_link href="/guides/integrations/continuous-integration#authentication">认证</.localized_link>。

对于由 Xcodebuild 驱动的 CI，你需要：
- 在调用 `xcodebuild` 操作时使用 <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link>。
- 将 `-resultBundlePath` 添加到你的 `xcodebuild` 命令中。

如果没有 `-resultBundlePath`，则不会生成所需的活动日志和结果包，`tuist inspect build` 也无法分析构建。

## 私有网络上的无凭据报告 {#network-trusted-publishing}

自托管部署可以允许开发者在不登录的情况下发布已完成的报告。操作员必须在实例上配置 `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` 并按照<.localized_link href="/guides/server/self-host/server#network-trusted-access">自托管指南</.localized_link>中的描述重新启动它。这适用于每个支持的项目；没有仪表板设置。在你的 scheme post-action 或终端使用的环境中配置自托管 URL 和项目。当缺少凭据时，CLI 会自动发现实例策略：

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

在真正缺少凭据的情况下，活动日志和 XCResult 包会在本地解析并作为结构化报告发送。不会提交原始归档、附件、覆盖率/历史记录上传、远程处理器、分片引用或选择性执行证据。报告仍然可见，但无法更新已认证的测试用例状态或驱动隔离/失败自动化。仪表板和其他特权命令仍然需要登录。除非实例单独启用了网络信任的缓存访问或提供了凭据，否则请保持缓存集成禁用。

现有凭据保持已认证状态。无效、损坏、空白或被拒绝刷新的凭据会静默失败并保留在磁盘上，因此后续命令不会无声地变为未签名。再次登录或显式注销作为有意识的恢复操作。在升级无凭据客户端之前，将每个服务器副本升级到支持发现的版本，并配置最终服务器 URL 而不使用重定向。较旧的没有发现功能的服务器、禁用的实例和发现失败仍然需要身份验证。不需要客户端选择加入。独立设置 `TUIST_ACTOR_ID=""` 以省略已配置的 actor claim；已验证的凭据身份不受影响。

## 机器指标 {#machine-metrics}

构建洞察可以包括在构建期间捕获的机器级性能指标（CPU、内存、网络和磁盘使用情况）。要启用此功能，请设置一个轻量级后台守护进程，持续采样系统指标：

```bash
tuist setup insights
```

这会运行一个在后台采样指标的本地守护进程。数据由 `tuist inspect build` 自动获取并与构建报告一起上传。

> [!TIP]
> **Ci**
>
> 在构建之前在 CI 机器上运行 `tuist setup insights`，以在那里也捕获机器指标。

要停止收集机器指标，请运行：

```bash
tuist teardown insights
```

这会卸载守护进程的 LaunchAgent，删除其 plist，并从 `~/.local/state` 删除采样的指标和守护进程日志，因此后台不会留下任何正在运行的内容。


## 报告 actor claim {#report-actor-claim}

仅当你将 `TUIST_ACTOR_ID` 显式设置为组织范围的标签（例如 `TUIST_ACTOR_ID=employee-123 tuist inspect build`）时，创建报告的请求才会包含可选的 `x-tuist-actor-id` 标头。默认情况下不发送标签，Tuist 也不会检测操作系统用户名。空的 `TUIST_ACTOR_ID` 会省略报告的标识符，但不会删除基于凭据的已验证身份。标识符必须是 1–128 字节的非空格可打印 ASCII；无效的覆盖会被省略且不回退。如果自定义代理拒绝不熟悉的标头，请使用空环境覆盖来选择退出。

已验证的个人凭据优先；否则，客户端报告的标识符显示为**未验证**，并且永远不会授予权限或自动链接到用户。任何可以查看项目报告的人都可以看到标识符，包括项目公开时的公共查看者，并且它们包含在数据导出中，因此不要包含机密。这适用于构建、测试和命令事件报告。旧服务器忽略可选标头，新服务器接受没有它的旧客户端。没有标识符的新共享令牌报告显示**未知**，而不是发布组织；历史报告保留其先前的归属。构建和测试列表区分已验证用户和未验证的报告标识符。除非自托管实例显式启用无凭据报告且客户端发现该策略，否则仍然需要身份验证。

## 自定义元数据 {#custom-metadata}

你可以通过环境变量将元数据附加到构建中，以改进过滤。

### 环境变量

| 变量 | 格式 | 描述 |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | 逗号分隔 | 在一个变量中包含多个标签。 |
| `TUIST_BUILD_VALUE_*` | 单个值 | 键值对，其中后缀为键。 |

### 示例

在调用构建之前，在 CI 或你的 shell 中设置这些值：

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
