---
{
  "title": "发布渠道",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "了解 Tuist 如何通过 Canary、候选版本和稳定渠道交付 CLI，以及如何将团队锁定在值得信赖的版本线上。"
}
---

# 发布渠道 {#release-channels}

Tuist CLI 通过三个渠道分发，各自提供不同的稳定性保障。推荐安装的是 **stable**，更新节奏较慢：它不会在每次功能合并时推进，因此升级不再意味着吸收一批无关的变更。早期采用者仍可在 **canary** 上运行按提交构建的版本，而 **release candidate** 渠道让团队在版本变为稳定之前先行试用即将发布的分支。

## 当前发布 {#live-release-status}

稳定版晋升安排在每周一 06:00 UTC。在成功的计划晋升之后，下一个发布候选版将从 `main` 切出，随后的 canary 版本将进入下一个小版本。查看 <.localized_link href="/cli/release/calendar">发布日历</.localized_link> 了解 upcoming 窗口和近期发布，包括补丁和回port。

<.release_status status={@release_status} components="cli" calendar_path="/cli/release/calendar" locale={@locale} />

## 渠道 {#the-channels}

| 渠道 | 版本格式 | 频率 | 默认解析？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `4.201.0-canary.42`） | 每次向 `main` 提交 | 否 — 需显式选择 |
| Release candidate | `X.Y.0-rc.N`（例如 `4.200.0-rc.1`） | 每周一从 `main` 切出，试用约 1 周 | 否 — 需显式选择 |
| Stable | `X.Y.Z`（例如 `4.200.0`、`4.200.1`） | 在顺利试用后，每周一晋升 | **是** |

Canary 和 release candidate 构建以预发布形式发布。Mise 和 Homebrew 等工具在解析 `latest`、裸安装或固定分支时会排除预发布版本，因此只有在你显式请求时才会使用它们。

### Canary {#canary}

每次向 `main` 提交都会发布一个 canary 版本。Canary 始终代表 **下一个未发布的小版本**：一旦为发布切出一个分支，`main` 就会推进到下一个小版本（例如，从 `4.200.0-canary.42` 到 `4.201.0-canary.1`）。如果你希望尽早获得信号，或者想在修复进入 stable 之前验证你报告或贡献的修复是否按预期工作，canary 是合适的渠道。

### Release candidate {#release-candidate}

当一个小版本准备发布时，其分支会被冻结到受保护的 `releases/<major>.<minor>.x` 分支，并以 `X.Y.0-rc.1` 的形式发布。该分支处于功能冻结状态；仅挑选关键修复和回归修复，每个被接受的修复都会递增 RC 版本号（`-rc.2`、`-rc.3`、…）。在试用期顺利结束后，该分支将晋升为 stable。

### Stable {#stable}

Stable 是推荐渠道，也是所有文档指向的渠道。只有在 release candidate 顺利试用后，才会发布 stable 小版本（`X.Y.0`），并且当新功能合并到 `main` 时，它 **不会** 推进。stable 分支上的补丁（`X.Y.1`、`X.Y.2`、…）仅包含回port 的修复，从不包含新功能。

## 选择版本 {#choosing-a-version}

使用 <.localized_link href="/guides/install-tuist">Mise</.localized_link>（推荐）：

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

使用 Homebrew 时，`brew install --formula tuist` 始终安装最新的 stable；预发布版本不通过 formula 分发。

## 推荐策略 {#recommended-strategy}

1. **固定到 stable 分支**，例如 `tuist@4.200`。该分支仅接收回port 的修复，从不接收新功能，因此日常升级保持低风险。
2. **有意识地采用新功能。** 当你准备好使用下一个小版本时，先在 release candidate 渠道上试用，然后将你的固定点移动到新的 stable 分支。
3. 如果你是希望尽早获得信号的早期采用者，可以在非关键环境中 **尝试 canary**。

## 支持与回port {#support-and-backports}

任何时候都有两个 stable 分支处于积极维护状态：

| 分支 | 接收 |
| --- | --- |
| 当前（`X.Y.x`） | 回归问题和安全修复 |
| 上一个（`X.(Y-1).x`） | 仅限关键修复和安全修复 |
| 更早版本 | 无 — 请升级到受维护的分支 |

修复首先合并到 `main`（canary）。回归问题和安全修复会回port 到当前 stable 分支，而上一个分支仅接收关键修复和安全修复。其他错误修复不会回port；它们将随下一个小版本发布。当新分支晋升为 stable 时，原当前分支变为“上一个”，而原“上一个”分支停止接收回port。

无论使用哪个渠道，Tuist 服务器都与过去 3 个月内发布的任何 CLI 保持 <.localized_link href="/cli/compatibility">兼容</.localized_link>，因此只要你在该期限内升级，固定到 stable 分支就不会让你超出支持范围。
