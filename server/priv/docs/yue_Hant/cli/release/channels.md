---
{
  "title": "發布渠道",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist 如何透過 Canary、候選版本（RC）及穩定版渠道發布 CLI，以及如何將團隊鎖定於你可信賴的發布線。"
}
---

# 發佈渠道 {#release-channels}

Tuist CLI 透過三個渠道發佈，各自提供不同的穩定性保證。建議安裝 **stable** 渠道，更新節奏較慢：它不會在每次功能合併時推進，因此升級不再意味著要吸收一批不相關的變更。早期採用者仍可在 **canary** 上執行每次提交的構建，而 **release candidate** 渠道讓團隊在版本變為穩定之前先行試用即將推出的版本線。

## 目前版本 {#live-release-status}

穩定版推廣安排於每週一 UTC 06:00 進行。成功完成預定推廣後，下一個候選版本會從 `main` 切出，隨後的 canary 則轉入下一個次版本。請參閱 <.localized_link href="/cli/release/calendar">發佈日曆</.localized_link> 以了解即將到來的時間窗口及近期發佈，包括修補程式和回溯移植。

<.release_status status={@release_status} components="cli" calendar_path="/cli/release/calendar" locale={@locale} />

## 渠道 {#the-channels}

| 渠道 | 版本格式 | 頻率 | 預設解析？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `4.201.0-canary.42`） | 每次提交至 `main` | 否 — 需明確選擇加入 |
| Release candidate | `X.Y.0-rc.N`（例如 `4.200.0-rc.1`） | 每週一從 `main` 切出，試用約 1 週 | 否 — 需明確選擇加入 |
| Stable | `X.Y.Z`（例如 `4.200.0`、`4.200.1`） | 經過乾淨試用後，每週一推廣 | **是** |

Canary 和 release candidate 構建以預發佈形式發佈。Mise 和 Homebrew 等工具在解析 `latest`、裸安裝或版本線鎖定時會排除預發佈版本，因此只有當你明確指定時才會使用它們。

### Canary {#canary}

每次提交至 `main` 都會發佈一個 canary。Canary 始終代表 **下一個未發佈的次版本**：一旦某個版本線被切出用於發佈，`main` 就會推進到下一個次版本（例如從 `4.200.0-canary.42` 到 `4.201.0-canary.1`）。如果你屬於希望盡早獲得信號的早期採用者，或者希望在修復進入穩定版之前驗證你所報告或貢獻的修復是否按預期運作，canary 是合適的渠道。

### Release candidate {#release-candidate}

當某個次版本準備好發佈時，其版本線會被凍結到受保護的 `releases/<major>.<minor>.x` 分支，並以 `X.Y.0-rc.1` 形式發佈。該版本線的功能已凍結；只會挑選關鍵修復和回歸問題，每個被接受的修復都會遞增 RC 編號（`-rc.2`、`-rc.3`、…）。經過乾淨的試用期後，該版本線會推廣為穩定版。

### Stable {#stable}

Stable 是建議使用的渠道，也是所有文件指向的渠道。穩定次版本（`X.Y.0`）只有在候選版本經過乾淨試用後才會發佈，並且當新功能合併到 `main` 時，它 **不會** 推進。穩定版本線上的修補程式（`X.Y.1`、`X.Y.2`、…）只包含回溯移植的修復，絕不包含新功能。

## 選擇版本 {#choosing-a-version}

使用 <.localized_link href="/guides/install-tuist">Mise</.localized_link>（建議）：

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

使用 Homebrew 時，`brew install --formula tuist` 始終安裝最新的穩定版；預發佈版本不會透過 formula 分發。

## 建議策略 {#recommended-strategy}

1. **鎖定到穩定版本線**，例如 `tuist@4.200`。該版本線只接收回溯移植的修復，絕不包含新功能，因此日常升級風險較低。
2. **有意識地採用新功能。** 當你準備好迎接下一個次版本時，先在 release candidate 渠道上試用，然後將你的鎖定移到新的穩定版本線。
3. 如果你是希望盡早獲得信號的早期採用者，可以在非關鍵環境中 **嘗試 canary**。

## 支援與回溯移植 {#support-and-backports}

任何時候都會積極維護兩個穩定版本線：

| 版本線 | 接收 |
| --- | --- |
| 當前（`X.Y.x`） | 回歸問題和安全修復 |
| 上一個（`X.(Y-1).x`） | 僅關鍵和安全修復 |
| 更舊版本 | 無 — 請升級至受維護的版本線 |

修復會先合併到 `main`（canary）。回歸問題和安全修復會回溯移植到當前穩定版本線，而上一個版本線只接收關鍵和安全修復。其他錯誤修復不會回溯移植；它們會隨下一個次版本發佈。當新版本線推廣為穩定版時，原來的「當前」版本線會變成「上一個」，而原來的「上一個」版本線則停止接收回溯移植。

無論使用哪個渠道，Tuist server 都與過去 3 個月內發佈的任何 CLI 保持<.localized_link href="/cli/compatibility">相容</.localized_link>，因此只要你在該期間內升級，鎖定到穩定版本線就不會讓你超出支援範圍。
