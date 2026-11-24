---
{
  "title": "發布渠道",
  "titleTemplate": ":title | 自行託管 | Server | 指南 | Tuist",
  "description": "Tuist 如何透過 Canary、候選版本及穩定渠道發佈伺服器同 Kura Docker 映像，以及點樣將你嘅部署鎖定喺一個可靠嘅版本線。"
}
---

# 發佈渠道 {#release-channels}

Tuist 伺服器同 Kura 快取伺服器透過三個 GHCR 映像渠道發佈，各自提供唔同嘅穩定性保證。建議安裝 **stable**，每週更新一次：佢唔會每次有功能合併到 `main` 就升級，所以升級唔再意味要吸收一批無關嘅變更。早期採用者仍然可以喺 **canary** 運行每次提交嘅建置，而 **release candidate** 渠道則讓你在版本變為穩定之前預先試用。

伺服器同 Kura 都跟隨同一個每週發佈節奏，並與 <.localized_link href="/cli/release/channels">Tuist CLI 的發佈時間表</.localized_link> 同步進行。

## 當前版本 {#live-release-status}

下方顯示各元件的當前版本。請參閱 <.localized_link href="/guides/server/self-host/release/calendar">發佈日曆</.localized_link> 以了解即將到來的發佈窗口和最近發佈的版本，包括修補程式和回溯移植。

<.release_status status={@release_status} components="server,kura" calendar_path="/guides/server/self-host/release/calendar" locale={@locale} />

## 渠道 {#the-channels}

| 渠道 | 版本格式 | 頻率 | 會移動 `:latest` 嗎？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `1.351.0-canary.5`） | 每次提交到 `main` | 否，需明確選擇加入 |
| Release candidate | `X.Y.0-rc.N`（例如 `1.351.0-rc.1`） | 每週一從 `main` 切出，試用約 1 週 | 否，需明確選擇加入 |
| Stable | `X.Y.Z`（例如 `1.350.2`、`1.351.0`） | 經過乾淨試用後，於每週一提升 | **是** |

Canary 和 release-candidate 建置會以 GitHub 預發佈版本形式發佈。任何在解析 `:latest` 時排除預發佈版本的工具都會跳過它們，因此你只有明確請求時才會使用其中一個。

### Canary {#canary}

每次提交到 `main` 都會發佈一個 canary 映像。Canary 始終代表 **下一個未發佈的次要版本**：一旦某個版本線被切出用於發佈，`main` 就會推進到下一個次要版本（例如，從 `1.350.0-canary.42` 到 `1.351.0-canary.1`）。Canary 是適合用於模擬生產環境的暫存環境的渠道，可讓你最早收到回歸問題的信號，或驗證你報告的修復在進入穩定版之前是否按預期運作。

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

當某個次要版本準備好發佈時，其版本線會被凍結到受保護的 `releases/server-<major>.<minor>.x`（或 `releases/kura-<major>.<minor>.x`）分支，並以 `X.Y.0-rc.1` 形式發佈。該版本線的功能已凍結；只有關鍵修復和回歸問題會被揀選進去，每個接受的修復都會迭代 release candidate 版本（`-rc.2`、`-rc.3` 等）。經過乾淨的試用期後，該版本線會在下一個星期一提升為穩定版。

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stable 是建議使用的渠道，也是所有文件指向的渠道。穩定版的次要版本（`X.Y.0`）只有在 release candidate 經過乾淨試用後才會發佈，並且當新功能合併到 `main` 時它 **不會** 推進。穩定版本線上的修補程式（`X.Y.1`、`X.Y.2` 等）只包含回溯移植的修復，絕不包含新功能。`:latest` 只在穩定版提升時移動。

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## 星期一列車 {#the-monday-train}

每週一 UTC 時間 06:00，三個元件的發佈列車會同步啟動：

1. **UTC 06:00** — 執行提升作業。每個作業會提升最新的尚未穩定的 release-candidate 版本線（通常是上週一切出的版本線），如果沒有則不執行任何操作。
2. **每次提升完成後** — release-candidate 作業會從 `main` 切出下一個版本線，因此剛切出的版本線不會在同一輪運行中被提升。

失敗的提升會暫緩切出版本線：系統只會選擇高於最新穩定版的最高 release-candidate 版本線，因此在失敗基礎上切出下一個版本線會導致未發佈的版本線被擱置。下週一會自動重試被暫緩的版本線。

## 固定渠道 {#pinning-a-channel}

在你的部署清單、Helm 值或 Docker Compose 文件中固定你想要的特定標籤。例如，使用 Helm chart：

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

`:latest` 在 `ghcr.io/tuist/tuist` 和 `ghcr.io/tuist/kura` 上都追蹤最新的穩定版，僅在星期一提升時移動。固定 `:latest` 可讓你獲得每週穩定版的節奏，而無需更新標籤；固定特定版本則可讓你完全控制升級時機。

## 建議策略 {#recommended-strategy}

這些渠道的存在是為了讓你可以將「獲取最新修復」與「獲取最新功能」分開。一個安全且低努力的預設做法是：

1. **將生產環境固定到一個穩定的次要版本線**，例如 `ghcr.io/tuist/tuist:1.351`。該版本線只接收回溯移植的修復，絕不包含新功能，因此日常升級風險較低。當你準備採用下一個次要版本時，再更新固定版本。
2. **在 canary 或特定的 release-candidate 標籤上運行暫存環境。** 暫存環境能攔截否則會到達用戶手中的回歸問題，而且暫存環境追蹤 `main` 越接近，你就越早發現這些問題。在當前的 release-candidate 版本線上運行暫存環境是一個很好的折衷方案：它會試用下週一將成為穩定版的確切字節。
3. **參閱[Server changelog](/changelog)以了解實際發佈的內容。** 每次穩定版提升都會在那裡宣佈，並列出已合併的 pull request 清單。

如果你希望新功能在成為穩定版後自動滾動到生產環境，請將生產環境保持在 `:latest`。只需注意標籤會在每週一早上推進，因此請相應安排你的部署時間窗口。

## 回溯移植 {#backports}

任何時候都有兩個穩定的 server（和 Kura）版本線處於積極維護狀態：當前版本線會以回溯移植 pull request 的形式接收回歸問題和安全修復，而上一個版本線只接收關鍵和安全修復。較舊的版本線不會進行回溯移植；請升級到受維護的版本線以接收修復。當新版本線被提升為穩定版時，原來的當前版本線變為「上一個」，而原來的「上一個」版本線則停止接收回溯移植。

回溯移植會按需作為 `X.Y.(Z+1)` 修補程式版本切出。它們絕不會移動 `:latest`。
