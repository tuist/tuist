---
{
  "title": "發布管道",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "了解 Tuist 如何透過 Canary、候選版本與穩定版管道交付 CLI，以及如何將團隊固定在可信任的版本線。"
}
---

# 發布管道 {#release-channels}

Tuist CLI 透過三種管道發布，各自提供不同的穩定性保證。建議的安裝版本為 **stable**，更新節奏較慢：它不會在每次功能合併時就推進，因此升級不再意味著要吸收一批不相關的變更。早期採用者仍可在 **canary** 上執行每次提交的建置，而 **release candidate** 管道則讓團隊在即將發布的版本線成為穩定版之前先行試用。

## 管道 {#the-channels}

| 管道 | 版本格式 | 更新頻率 | 預設解析？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `4.201.0-canary.42`） | 每次提交至 `main` | 否 — 需明確選擇加入 |
| Release candidate | `X.Y.0-rc.N`（例如 `4.200.0-rc.1`） | 每週一從 `main` 切出，試用約 1 週 | 否 — 需明確選擇加入 |
| Stable | `X.Y.Z`（例如 `4.200.0`、`4.200.1`） | 經過乾淨試用後，每週一升級 | **是** |

Canary 與 release candidate 建置會以預釋出版本發布。Mise 和 Homebrew 等工具在解析 `latest`、一般安裝或版本線鎖定時會排除預釋出版本，因此除非你明確指定，否則不會落到這些版本。

### Canary {#canary}

每次提交至 `main` 都會發布一個 canary 版本。Canary 始終代表 **下一個尚未發布的次要版本**：一旦某個版本線被切出準備發布，`main` 就會推進到下一個次要版本（例如從 `4.200.0-canary.42` 到 `4.201.0-canary.1`）。如果你希望盡早獲得最新訊號，或是想驗證你回報或貢獻的修正行為是否符合預期，再進入穩定版之前，canary 是適合早期採用者的管道。

### Release candidate {#release-candidate}

當某個次要版本準備發布時，其版本線會被凍結到受保護的 `releases/<major>.<minor>.x` 分支，並以 `X.Y.0-rc.1` 發布。該版本線的功能已凍結；只會挑選關鍵修正與回歸修復，每接受一個修正就會遞增 RC 版本（`-rc.2`、`-rc.3`、…）。經過乾淨的試用期後，該版本線會升級為穩定版。

### Stable {#stable}

Stable 是建議的管道，也是所有文件指向的版本。只有在 release candidate 經過乾淨試用後，才會發布穩定版的次要版本（`X.Y.0`），而且當新功能合併至 `main` 時，它並 **不會** 推進。穩定版本線上的修補版本（`X.Y.1`、`X.Y.2`、…）只包含回溯移植的修正，絕不包含新功能。

## 選擇版本 {#choosing-a-version}

使用 [Mise](/en/guides/install-tuist)（建議）：

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

使用 Homebrew 時，`brew install --formula tuist` 一律安裝最新的穩定版；預釋出版本不會透過公式發布。

## 建議策略 {#recommended-strategy}

1. **鎖定穩定版本線**，例如 `tuist@4.200`。該版本線只接收回溯移植的修正，絕不包含新功能，因此日常升級風險較低。
2. **刻意採用新功能。** 當你準備好迎接下一個次要版本時，先在 release candidate 管道上試用，然後將你的鎖定版本移至新的穩定版本線。
3. **嘗試 canary**：若你是希望盡早獲得最新訊號的早期採用者，可在非關鍵環境中試用。

## 支援與回溯移植 {#support-and-backports}

任何時候都會積極維護兩條穩定版本線：

| 版本線 | 接收內容 |
| --- | --- |
| 目前（`X.Y.x`） | 回歸修復與安全性修正 |
| 前一版（`X.(Y-1).x`） | 僅限關鍵修正與安全性修正 |
| 更舊版本 | 無 — 請升級至受維護的版本線 |

修正會先合併至 `main`（canary）。回歸修復與安全性修正會回溯移植到目前的穩定版本線，而前一版版本線僅接收關鍵修正與安全性修正。其他錯誤修正不會回溯移植；它們會隨下一個次要版本發布。當新版本線升級為穩定版時，原本的「目前」版本線會變成「前一版」，而原本的「前一版」版本線則停止接收回溯移植。

無論使用哪種管道，Tuist 伺服器都與過去 3 個月內發布的任何 CLI 保持[相容](/en/cli/compatibility)，因此只要你在該期間內升級，鎖定穩定版本線就不會讓你超出支援範圍。
