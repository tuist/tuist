---
{
  "title": "发布渠道",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist 如何通过 Canary、候选版本和稳定渠道分发 CLI，以及如何将团队锁定在值得信赖的版本线上。"
}
---

# 发布渠道 {#release-channels}

Tuist CLI 通过三个渠道分发，各自提供不同的稳定性保障。推荐安装的是 **稳定版**，更新节奏较慢：它不会在每次功能合并时都前进，因此升级不再意味着要吸收一批不相关的变更。早期采用者仍可在 **Canary** 渠道运行每次提交的构建，而 **候选发布** 渠道则让团队在版本变为稳定之前先行试用即将发布的分支。

## 各渠道 {#the-channels}

| 渠道 | 版本格式 | 发布频率 | 默认解析？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `4.201.0-canary.42`） | 每次向 `main` 提交 | 否——需显式选择 |
| 候选发布 | `X.Y.0-rc.N`（例如 `4.200.0-rc.1`） | 每周一从 `main` 切出，试用约 1 周 | 否——需显式选择 |
| 稳定版 | `X.Y.Z`（例如 `4.200.0`、`4.200.1`） | 在顺利试用后，每周一提升为稳定版 | **是** |

Canary 和候选发布构建以预发布形式发布。Mise 和 Homebrew 等工具在解析 `latest`、裸安装或固定分支时会排除预发布版本，因此只有在你显式请求时才会落到这些版本上。

### Canary {#canary}

每次向 `main` 的提交都会发布一个 Canary 版本。Canary 始终代表 **下一个未发布的小版本**：一旦为发布切出分支，`main` 就会前进到下一个小版本（例如，从 `4.200.0-canary.42` 到 `4.201.0-canary.1`）。对于希望获得最早信号，或在修复进入稳定版之前验证你报告或贡献的修复是否按预期工作的早期采用者来说，Canary 是合适的渠道。

### 候选发布 {#release-candidate}

当一个小版本准备发布时，其分支会被冻结到受保护的 `releases/<major>.<minor>.x` 分支，并以 `X.Y.0-rc.1` 的形式发布。该分支处于功能冻结状态；只会挑选关键修复和回归修复，每接受一个修复就会递增 RC 版本号（`-rc.2`、`-rc.3`、…）。在顺利度过试用期后，该分支会被提升为稳定版。

### 稳定版 {#stable}

稳定版是推荐渠道，也是所有文档指向的渠道。只有在候选发布顺利试用后，才会发布稳定小版本（`X.Y.0`），并且当新功能合并到 `main` 时，它 **不会** 前进。稳定分支上的补丁版本（`X.Y.1`、`X.Y.2`、…）仅包含回溯修复，从不包含新功能。

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

1. **固定到一个稳定分支**，例如 `tuist@4.200`。该分支仅接收回溯修复，从不包含新功能，因此日常升级风险较低。
2. **有计划地采用新功能。** 当你准备好使用下一个小版本时，先在候选发布渠道进行试用，然后将你的固定版本迁移到新的稳定分支。
3. 如果你是希望获得最早信号的早期采用者，可以在非关键环境中 **尝试 Canary**。

## 支持与回溯修复 {#support-and-backports}

任何时候都会积极维护两个稳定分支：

| 分支 | 接收内容 |
| --- | --- |
| 当前（`X.Y.x`） | 回归修复和安全修复 |
| 上一版本（`X.(Y-1).x`） | 仅关键修复和安全修复 |
| 更早版本 | 无 — 请升级到受维护的分支 |

修复首先合入 `main`（Canary）。回归修复和安全修复会被回溯到当前稳定分支，而上一版本分支仅接收关键修复和安全修复。其他错误修复不会回溯；它们将随下一个小版本发布。当新分支被提升为稳定版时，原当前分支变为“上一版本”，原“上一版本”分支停止接收回溯修复。

无论使用哪个渠道，Tuist 服务器都与过去 3 个月内发布的任何 CLI 保持 <.localized_link href="/cli/compatibility">兼容</.localized_link>，因此只要在此期间进行升级，固定到稳定分支就不会让你超出支持范围。
