---
{
  "title": "发布渠道",
  "titleTemplate": ":title | 自托管 | Server | 指南 | Tuist",
  "description": "了解 Tuist 如何在 Canary、Release Candidate 和 Stable 渠道分发 Server 和 Kura Docker 镜像，以及如何将部署固定到你可信赖的版本线。"
}
---

# 发布渠道 {#release-channels}

Tuist 服务器和 Kura 缓存服务器通过三个具有不同稳定性保证的 GHCR 镜像渠道发布。推荐安装的是 **stable**，每周更新一次：它不会在每次功能合并到 `main` 时都前进，因此升级不再意味着吸收一批不相关的更改。早期采用者仍然可以在 **canary** 上运行每次提交的构建，而 **release candidate** 渠道允许你在即将发布的版本线变得稳定之前对其进行试用。

服务器和 Kura 遵循相同的每周发布节奏，并且与 <.localized_link href="/cli/release/channels">Tuist CLI 的发布计划</.localized_link> 保持同步。

## 当前版本 {#live-release-status}

每个组件的当前版本如下所示。查看 <.localized_link href="/guides/server/self-host/release/calendar">发布日历</.localized_link> 以了解即将到来的发布窗口和最近的发布，包括补丁和回溯移植。

<.release_status status={@release_status} components="server,kura" calendar_path="/guides/server/self-host/release/calendar" locale={@locale} />

## 渠道 {#the-channels}

| 渠道 | 版本格式 | 频率 | 移动 `:latest`？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `1.351.0-canary.5`） | 每次提交到 `main` | 否，需明确选择加入 |
| Release candidate | `X.Y.0-rc.N`（例如 `1.351.0-rc.1`） | 每周一从 `main` 切出，试用约 1 周 | 否，需明确选择加入 |
| Stable | `X.Y.Z`（例如 `1.350.2`、`1.351.0`） | 在干净试用后，每周一提升 | **是** |

Canary 和 release-candidate 构建作为 GitHub 预发布版本发布。任何在解析 `:latest` 时排除预发布版本的工具都会跳过它们，因此你只有通过明确请求才能使用它们。

### Canary {#canary}

每次提交到 `main` 都会发布一个 canary 镜像。Canary 始终代表 **下一个未发布的小版本**：一旦为发布切出一个版本线，`main` 就会前进到下一个小版本（例如，从 `1.350.0-canary.42` 到 `1.351.0-canary.1`）。Canary 是适合暂存环境的渠道，它可以镜像生产环境并为你提供最早的回归信号，或者用于验证你报告的修复在达到 stable 之前是否按预期工作。

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

当一个小版本准备发布时，其版本线会被冻结到一个受保护的 `releases/server-<major>.<minor>.x`（或 `releases/kura-<major>.<minor>.x`）分支上，并发布为 `X.Y.0-rc.1`。该版本线功能冻结；只有关键修复和回归修复会被挑选到其中，每个接受的修复都会迭代 release candidate（`-rc.2`、`-rc.3` 等）。在试用期干净结束后，该版本线将在下周一提升为 stable。

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stable 是推荐渠道，也是所有文档指向的渠道。只有在 release candidate 干净试用后，才会发布 stable 小版本（`X.Y.0`），并且当新功能合并到 `main` 时，它 **不会** 前进。Stable 版本线上的补丁（`X.Y.1`、`X.Y.2` 等）仅包含回溯移植的修复，绝不包含新功能。`:latest` 仅在 stable 提升时移动。

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## 周一列车 {#the-monday-train}

每周一 UTC 06:00，三个组件的发布列车同步启动：

1. **06:00 UTC** — 运行提升作业。每个作业都会提升最新的尚未稳定的 release-candidate 版本线（通常是上周一切出的版本线），如果没有则不执行任何操作。
2. **每次提升完成后** — release-candidate 作业从 `main` 切出下一个版本线，因此新切出的版本线永远不会在同一次运行中被提升。

失败的提升会暂缓切出：只会选择高于最新 stable 的最高 release-candidate 版本线，因此在失败之上切出下一个版本线会导致未发布的版本线被孤立。下周一会自动重试被暂缓的版本线。

## 固定渠道 {#pinning-a-channel}

在你的部署清单、Helm 值或 Docker Compose 文件中固定你想要的特定标签。例如，使用 Helm chart：

```yaml
server:
  image:
    repository: ghcr.io/tuist/tuist
    tag: "1.350.2"          # Pinned to a stable patch
    # tag: "1.351.0-rc.1"   # Or opt into a release candidate to soak it
    # tag: "1.351.0-canary.5" # Or opt into a specific canary build

kuraRuntime:
  image:
    repository: ghcr.io/tuist/kura
    tag: "0.54.0"           # Same three channels apply to Kura
```

`:latest` 在 `ghcr.io/tuist/tuist` 和 `ghcr.io/tuist/kura` 上都跟踪最新的 stable，仅在周一提升时移动。固定 `:latest` 让你获得每周 stable 的节奏，而无需更新标签；固定特定版本让你完全控制升级时间。

## 推荐策略 {#recommended-strategy}

这些渠道的存在是为了让你能够将“获取最新修复”与“获取最新功能”解耦。一个安全、低努力的默认策略是：

1. **将生产环境固定到 stable 小版本线**，例如 `ghcr.io/tuist/tuist:1.351`。该版本线仅接收回溯移植的修复，绝不接收新功能，因此日常升级保持低风险。当你准备好采用下一个小版本时，再更新固定版本。
2. **在 canary 或特定的 release-candidate 标签上运行预发环境。** 预发环境能够捕获否则会影响用户的回归问题，并且预发环境跟踪 `main` 越紧密，你就能越早发现这些问题。在当前 release-candidate 版本线上运行预发环境是一个不错的折中方案：它会试用将在下周一变为 stable 的确切字节。
3. **查阅[服务器变更日志](/changelog)以了解实际发布的内容。** 每次 stable 提升都会在此公布，并附带入选的拉取请求列表。

如果你希望新功能在变为 stable 后自动滚动到生产环境，请将生产环境保持在 `:latest`。请注意，该标签会在每周一上午推进，因此请相应安排你的部署窗口。

## 回溯移植 {#backports}

任何时候都有两条 stable 服务器（和 Kura）版本线处于积极维护状态：当前版本线通过回溯移植拉取请求接收回归修复和安全修复，而前一个版本线仅接收关键修复和安全修复。更旧的版本线不会进行回溯移植；请升级到受维护的版本线以获取修复。当新版本线被提升为 stable 时，原来的当前版本线变为“前一个”，而原来的“前一个”版本线则停止接收回溯移植。

回溯移植会按需切出为 `X.Y.(Z+1)` 补丁版本。它们永远不会移动 `:latest`。
