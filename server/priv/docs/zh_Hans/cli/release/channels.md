---
{
  "title": "发布渠道",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist 如何通过 Canary、候选版本和稳定渠道分发 CLI，以及如何将团队锁定在值得信赖的版本线上。"
}
---

# 发布渠道 {#release-channels}

Tuist CLI 通过三个渠道分发，各自提供不同的稳定性保证。推荐安装的是 **stable** 渠道，更新节奏较慢：它不会在每次功能合并时前进，因此升级不再意味着吸收一批不相关的变更。早期采用者仍可在 **canary** 渠道上运行每次提交的构建，而 **release candidate** 渠道则让团队在即将发布的版本线成为稳定版之前进行充分验证。

## 当前发布 {#live-release-status}

稳定版的晋升安排在每周一 06:00 UTC。在成功的计划晋升之后，下一个候选发布版会从 `main` 切出，随后的 canary 版本会进入下一个次版本。查看 <.localized_link href="/cli/release/calendar">发布日历</.localized_link> 了解即将到来的窗口期和近期发布，包括补丁和回溯修复。

<.release_status status={@release_status} components="cli" calendar_path="/cli/release/calendar" locale={@locale} />

## 渠道 {#the-channels}

| 渠道 | 版本格式 | 发布频率 | 默认解析？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `4.201.0-canary.42`） | 每次向 `main` 提交 | 否——需显式选择 |
| Release candidate | `X.Y.0-rc.N`（例如 `4.200.0-rc.1`） | 每周一从 `main` 切出，验证约 1 周 | 否——需显式选择 |
| Stable | `X.Y.Z`（例如 `4.200.0`、`4.200.1`） | 在干净验证后每周一晋升 | **是** |

Canary 和 release candidate 构建以预发布形式发布。Mise 和 Homebrew 等工具在解析 `latest`、裸安装或固定版本线时会排除预发布版本，因此只有在你显式请求时才会使用它们。

### Canary {#canary}

每次向 `main` 提交都会发布一个 canary 版本。Canary 始终代表 **下一个未发布的次版本**：一旦为发布切出一个版本线，`main` 就会前进到下一个次版本（例如，从 `4.200.0-canary.42` 到 `4.201.0-canary.1`）。对于希望尽早获得信号，或在修复进入稳定版之前验证你报告或贡献的修复是否按预期工作的早期采用者来说，Canary 是合适的渠道。

### Release candidate {#release-candidate}

当一个次版本准备发布时，其版本线会被冻结到受保护的 `releases/<major>.<minor>.x` 分支，并以 `X.Y.0-rc.1` 的形式发布。该版本线处于功能冻结状态；只会挑选关键修复和回归修复，每个被接受的修复都会递增 RC 编号（`-rc.2`、`-rc.3`、…）。在验证期顺利结束后，该版本线会晋升为稳定版。

### Stable {#stable}

Stable 是推荐渠道，也是所有文档指向的渠道。稳定版的次版本（`X.Y.0`）只有在候选发布版经过干净验证后才会发布，并且当新功能合并到 `main` 时它 **不会** 前进。稳定版本线上的补丁（`X.Y.1`、`X.Y.2`、…）仅包含回溯修复，绝不包含新功能。

## 选择版本 {#choosing-a-version}

使用 <.localized_link href="/guides/install-tuist">Mise</.localized_link>（推荐）：

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

使用 Homebrew 时，`brew install --formula tuist` 始终安装最新的稳定版；预发布版本不会通过该公式分发。

## 推荐策略 {#recommended-strategy}

1. **固定到一个稳定版本线**，例如 `tuist@4.200`。该版本线仅接收回溯修复，不包含新功能，因此日常升级风险较低。
2. **有意识地采用新功能。** 当你准备好进入下一个次版本时，先在 release candidate 渠道上进行验证，然后将你的固定版本迁移到新的稳定版本线。
3. 如果你是希望尽早获得信号的早期采用者，可以在非关键环境中 **尝试 canary**。

## 支持与回溯修复 {#support-and-backports}

任何时候都会积极维护两个稳定版本线：

| 版本线 | 接收 |
| --- | --- |
| 当前（`X.Y.x`） | 回归修复和安全修复 |
| 上一版本（`X.(Y-1).x`） | 仅关键修复和安全修复 |
| 更早版本 | 无 — 请升级到受维护的版本线 |

修复首先合并到 `main`（canary）。回归修复和安全修复会回溯到当前稳定版本线，而上一版本线仅接收关键修复和安全修复。其他错误修复不会回溯；它们将随下一次次版本发布。当新版本线晋升为稳定版时，原当前版本线变为“上一版本”，原“上一版本”线停止接收回溯修复。

无论使用哪个渠道，Tuist 服务器都 <.localized_link href="/cli/compatibility">兼容</.localized_link> 过去 3 个月内发布的任何 CLI，因此只要你在此期间进行升级，固定到稳定版本线就不会让你超出支持范围。
