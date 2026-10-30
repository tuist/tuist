---
{
  "title": "发布渠道",
  "titleTemplate": ":title | 自托管 | Server | 指南 | Tuist",
  "description": "了解 Tuist 如何通过 Canary、Release Candidate 和 Stable 渠道分发 Server 和 Kura Docker 镜像，以及如何将部署固定到你可信赖的版本线。"
}
---

# 发布渠道 {#release-channels}

Tuist 服务器和 Kura 缓存服务器通过三个具有不同稳定性保证的 GHCR 镜像渠道进行交付。推荐安装的是 **stable**，每周更新一次：它不会在每次功能合并到 `main` 时都前进，因此升级不再意味着吸收一批不相关的更改。早期采用者仍然可以在 **canary** 上运行每次提交的构建，而 **release candidate** 渠道则允许你在即将发布的版本变为稳定版之前对其进行充分测试。

服务器和 Kura 遵循相同的每周发布节奏，并与 [Tuist CLI 的发布计划](/en/cli/release-channels) 保持同步。

## 渠道 {#the-channels}

| 渠道 | 版本格式 | 发布频率 | 是否更新 `:latest`？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `1.351.0-canary.5`） | 每次提交到 `main` | 否，需显式选择 |
| Release candidate | `X.Y.0-rc.N`（例如 `1.351.0-rc.1`） | 每周一从 `main` 切分，测试约 1 周 | 否，需显式选择 |
| Stable | `X.Y.Z`（例如 `1.350.2`、`1.351.0`） | 经过充分测试后，每周一提升 | **是** |

Canary 和 release-candidate 构建作为 GitHub 预发布版本发布。任何在解析 `:latest` 时排除预发布版本的工具都会跳过它们，因此只有在你显式请求时才会使用这些版本。

### Canary {#canary}

每次提交到 `main` 都会发布一个 canary 镜像。Canary 始终代表 **下一个未发布的小版本**：一旦为发布切分了某个版本线，`main` 就会前进到下一个小版本（例如，从 `1.350.0-canary.42` 到 `1.351.0-canary.1`）。Canary 是适合用于模拟生产环境的暂存环境的正确渠道，它能让你尽早收到回归问题的信号，或者在修复进入稳定版之前验证你报告的问题是否已按预期解决。

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

当一个小版本准备发布时，其版本线会被冻结到一个受保护的 `releases/server-<major>.<minor>.x`（或 `releases/kura-<major>.<minor>.x`）分支上，并发布为 `X.Y.0-rc.1`。该版本线处于功能冻结状态；只有关键修复和回归问题会被挑选合并到其中，每个被接受的修复都会迭代 release candidate 版本（`-rc.2`、`-rc.3` 等）。在经过充分的测试期且结果良好后，该版本线将在下一个周一提升为稳定版。

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stable 是推荐渠道，也是所有文档指向的渠道。稳定版小版本（`X.Y.0`）仅在 release candidate 经过充分测试且结果良好后才会发布，并且当新功能合并到 `main` 时，它 **不会** 前进。稳定版本线上的补丁版本（`X.Y.1`、`X.Y.2` 等）仅包含向后移植的修复，绝不包含新功能。`:latest` 仅在稳定版提升时更新。

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## 周一发布列车 {#the-monday-train}

每周一 UTC 时间 06:00，三个组件的发布列车会同步启动：

1. **06:00 UTC** — 执行提升作业。每个作业都会提升最新的尚未成为稳定版的 release-candidate 版本线（通常是上一个周一切分的版本线），如果没有这样的版本线，则不执行任何操作。
2. **每次提升完成后** — release-candidate 作业会从 `main` 切分下一个版本线，因此刚切分的版本线不会在同一次运行中被提升。

如果提升失败，切分操作将被搁置：系统只会选择高于最新稳定版的最高 release-candidate 版本线，因此在失败基础上切分下一个版本线会导致未发布的版本线被孤立。下一个周一会自动重试被搁置的版本线。

## 固定渠道 {#pinning-a-channel}

在部署清单、Helm 值或 Docker Compose 文件中固定你想要的特定标签。例如，使用 Helm chart：

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

`:latest` 在 `ghcr.io/tuist/tuist` 和 `ghcr.io/tuist/kura` 上都跟踪最新的稳定版，仅在周一提升时更新。固定 `:latest` 可让你获得每周的稳定版更新节奏，而无需手动更新标签；固定特定版本则可让你完全控制升级时间。

## 推荐策略 {#recommended-strategy}

这些渠道的存在是为了让你能够将“获取最新修复”与“获取最新功能”解耦。一个安全且低成本的默认策略是：

1. **将生产环境固定到一个稳定的小版本线**，例如 `ghcr.io/tuist/tuist:1.351`。该版本线仅接收向后移植的修复，从不包含新功能，因此日常升级风险较低。当你准备好采用下一个小版本时，再更新固定的版本。
2. **在 canary 或特定的 release-candidate 标签上运行暂存环境。** 暂存环境可以捕获否则会影响用户的回归问题，而且暂存环境越接近 `main`，你就能越早发现这些问题。在当前 release-candidate 版本线上运行暂存环境是一个不错的折中方案：它会充分测试将在下一个周一成为稳定版的确切代码。
3. **关注 [服务器变更日志](/changelog) 以了解实际发布的内容。** 每次稳定版提升都会在那里公布，并附带入选的拉取请求列表。

如果你希望新功能在成为稳定版后自动滚动发布到生产环境，请让生产环境继续使用 `:latest`。请注意，该标签会在每周一上午更新，因此请相应安排你的部署窗口。

## 向后移植 {#backports}

任何时候都有两个稳定的服务器（以及 Kura）版本线处于积极维护状态：当前版本线会通过向后移植的拉取请求接收回归修复和安全修复，而前一个版本线仅接收关键修复和安全修复。更旧的版本线不会进行向后移植；请升级到受维护的版本线以获取修复。当新版本线被提升为稳定版时，原来的当前版本线变为“前一个”，而原来的“前一个”版本线则停止接收向后移植。

向后移植会按需切分为 `X.Y.(Z+1)` 补丁版本发布。它们永远不会移动 `:latest`。
