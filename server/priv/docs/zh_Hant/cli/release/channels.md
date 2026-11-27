---
{
  "title": "發布管道",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "了解 Tuist 如何透過 Canary、候選版本與穩定管道交付 CLI，以及如何將團隊鎖定在值得信賴的發布線。"
}
---

# 發布管道 {#release-channels}

Tuist CLI 透過三個管道發布，各自提供不同的穩定性保證。建議的安裝版本為 **stable**，更新節奏較慢：它不會在每次功能合併時推進，因此升級不再意味著吸收一批不相干的變更。早期採用者仍可在 **canary** 上執行每次提交的建置，而 **release candidate** 管道則讓團隊在版本成為穩定版之前，先行試用即將推出的版本線。

## 目前發布版本 {#live-release-status}

穩定版推廣排程於每週一 06:00 UTC。在成功的預定推廣後，下一個候選發布版會從 `main` 切出，後續的 canary 版本則移至下一個次要版本。請參閱 <.localized_link href="/cli/release/calendar">發布行事曆</.localized_link> 以了解即將到來的發布視窗與近期發布，包含修補程式與回溯移植。

<.release_status status={@release_status} components="cli" calendar_path="/cli/release/calendar" locale={@locale} />

## 管道 {#the-channels}

| 管道 | 版本格式 | 頻率 | 預設解析？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `4.201.0-canary.42`） | 每次提交至 `main` | 否 — 需明確選擇加入 |
| Release candidate | `X.Y.0-rc.N`（例如 `4.200.0-rc.1`） | 每週一從 `main` 切出，試用約 1 週 | 否 — 需明確選擇加入 |
| Stable | `X.Y.Z`（例如 `4.200.0`、`4.200.1`） | 經過乾淨的試用期後，於每週一推廣 | **是** |

Canary 與 release candidate 建置以預發布形式發布。Mise 和 Homebrew 等工具在解析 `latest`、一般安裝或版本線鎖定時會排除預發布版本，因此除非你明確指定，否則不會安裝到這些版本。

### Canary {#canary}

每次提交至 `main` 都會發布一個 canary 版本。Canary 始終代表 **下一個尚未發布的次要版本**：一旦為發布切出版本線，`main` 就會推進至下一個次要版本（例如從 `4.200.0-canary.42` 到 `4.201.0-canary.1`）。對於希望盡早獲得訊號的早期採用者，或希望在修復進入穩定版之前驗證其行為是否符合預期的人來說，Canary 是合適的管道。

### Release candidate {#release-candidate}

當某個次要版本準備好發布時，其版本線會被凍結至受保護的 `releases/<major>.<minor>.x` 分支，並以 `X.Y.0-rc.1` 的形式發布。該版本線的功能已凍結；僅會挑選關鍵修復與回歸問題，且每個接受的修復都會遞增 RC 版本號（`-rc.2`、`-rc.3`、…）。在試用期順利結束後，該版本線會推廣為穩定版。

### Stable {#stable}

Stable 是建議的管道，也是所有文件指向的版本。穩定次要版本（`X.Y.0`）僅在候選發布版經過乾淨的試用期後才會發布，且當新功能合併至 `main` 時，它 **不會** 推進。穩定版本線上的修補程式（`X.Y.1`、`X.Y.2`、…）僅包含回溯移植的修復，絕不包含新功能。

## 選擇版本 {#choosing-a-version}

使用 <.localized_link href="/guides/install-tuist">Mise</.localized_link>（建議）：

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

使用 Homebrew 時，`brew install --formula tuist` 一律安裝最新的穩定版；預發布版本不會透過公式分發。

## 建議策略 {#recommended-strategy}

1. **鎖定穩定版本線**，例如 `tuist@4.200`。該版本線僅接收回溯移植的修復，絕不包含新功能，因此日常升級風險較低。
2. **謹慎採用新功能。** 當你準備好迎接下一個次要版本時，先在 release candidate 管道上試用，然後將你的鎖定版本移至新的穩定版本線。
3. 如果你是希望盡早獲得訊號的早期採用者，可以在非關鍵環境中 **嘗試 canary**。

## 支援與回溯移植 {#support-and-backports}

任何時候都會積極維護兩個穩定版本線：

| 版本線 | 接收 |
| --- | --- |
| 目前（`X.Y.x`） | 回歸問題與安全性修復 |
| 先前（`X.(Y-1).x`） | 僅限關鍵與安全性修復 |
| 更舊版本 | 無 — 請升級至受維護的版本線 |

修復會先合併至 `main`（canary）。回歸問題與安全性修復會回溯移植至目前的穩定版本線，而先前版本線僅接收關鍵與安全性修復。其他錯誤修復不會回溯移植；它們會隨下一個次要版本發布。當新版本線推廣為穩定版時，原本的目前版本線會變成「先前」，而原本的「先前」版本線則停止接收回溯移植。

無論使用哪個管道，Tuist 伺服器都與過去 3 個月內發布的任何 CLI 保持<.localized_link href="/cli/compatibility">相容</.localized_link>，因此只要你在該期間內升級，鎖定穩定版本線就不會讓你超出支援範圍。
