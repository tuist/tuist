---
{
  "title": "發布管道",
  "titleTemplate": ":title | 自行託管 | Server | 指南 | Tuist",
  "description": "Tuist 如何透過 Canary、Release Candidate 和 Stable 管道發布伺服器與 Kura Docker 映像，以及如何將部署固定於你可信賴的發布線。"
}
---

# 發布管道 {#release-channels}

Tuist 伺服器與 Kura 快取伺服器透過三個 GHCR 映像檔管道發布，各自提供不同的穩定性保證。建議安裝 **stable** 頻道，每週更新一次：它不會在每次功能合併至 `main` 時就推進，因此升級不再意味著吸收一批不相干的變更。早期採用者仍可在 **canary** 上執行每次提交的建置，而 **release candidate** 頻道則讓你在版本穩定前先對即將推出的版本進行浸泡測試。

伺服器與 Kura 都搭乘相同的每週列車，並與 <.localized_link href="/cli/release/channels">Tuist CLI 的發布時程</.localized_link> 同步觸發。

## 目前發布版本 {#live-release-status}

下方顯示各元件目前的發布版本。請參閱 <.localized_link href="/guides/server/self-host/release/calendar">發布日曆</.localized_link>，了解即將到來的發布視窗與近期發布，包含修補程式與回溯移植。

<.release_status status={@release_status} components="server,kura" calendar_path="/guides/server/self-host/release/calendar" locale={@locale} />

## 管道 {#the-channels}

| 管道 | 版本格式 | 頻率 | 是否推進 `:latest`？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `1.351.0-canary.5`） | 每次提交至 `main` | 否，需明確選擇加入 |
| Release candidate | `X.Y.0-rc.N`（例如 `1.351.0-rc.1`） | 每週一從 `main` 切出，浸泡約 1 週 | 否，需明確選擇加入 |
| Stable | `X.Y.Z`（例如 `1.350.2`、`1.351.0`） | 在乾淨浸泡後，於每週一推進 | **是** |

Canary 與 release-candidate 建置會以 GitHub 預發布形式發布。任何在解析 `:latest` 時排除預發布版本的工具都會略過它們，因此只有當你明確要求時才會使用其中任一版本。

### Canary {#canary}

每次提交至 `main` 都會發布一個 canary 映像檔。Canary 始終代表 **下一個尚未發布的次要版本**：一旦為發布切出一條分支線，`main` 就會推進至下一個次要版本（例如從 `1.350.0-canary.42` 到 `1.351.0-canary.1`）。Canary 適合用於鏡像生產環境的暫存環境，讓你盡早收到回歸問題的訊號，或在修復進入 stable 之前驗證你回報的修正是否符合預期。

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

當某個次要版本準備好交付時，其分支線會被凍結到受保護的 `releases/server-<major>.<minor>.x`（或 `releases/kura-<major>.<minor>.x`）分支，並以 `X.Y.0-rc.1` 發布。該分支線功能凍結；只會挑選關鍵修正與回歸問題，且每個接受的修正都會遞增 release candidate 版本（`-rc.2`、`-rc.3`，依此類推）。在浸泡期順利結束後，該分支線將於下週一推進至 stable。

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stable 是建議使用的管道，也是所有文件指向的版本。只有在 release candidate 經過乾淨浸泡後，才會發布 stable 次要版本（`X.Y.0`），且當新功能合併至 `main` 時，它 **不會** 推進。stable 分支線上的修補程式（`X.Y.1`、`X.Y.2`，依此類推）僅包含回溯移植的修正，絕不包含新功能。`:latest` 僅在 stable 推進時才會移動。

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## 週一列車 {#the-monday-train}

每週一 UTC 06:00，三個元件的發布列車會同步觸發：

1. **UTC 06:00** — 執行推進作業。每個作業會推進最新且尚未成為 stable 的 release-candidate 分支線（通常是上週一切出的分支線），若沒有則不執行任何動作。
2. **每次推進完成後** — release-candidate 作業會從 `main` 切出下一條分支線，因此剛切出的分支線不會在同一輪執行中被推進。

若推進失敗，切出作業會暫停：系統只會挑選高於最新 stable 的最高 release-candidate 分支線，因此在失敗基礎上切出下一條分支線會讓未發布的分支線擱置。下週一會自動重試被擱置的分支線。

## 固定管道 {#pinning-a-channel}

在你的部署清單、Helm 值或 Docker Compose 檔案中固定你想要的特定標籤。以下是使用 Helm chart 的範例：

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

`:latest` 在 `ghcr.io/tuist/tuist` 與 `ghcr.io/tuist/kura` 上都會追蹤最新的 stable 版本，僅在週一推進時移動。固定 `:latest` 可讓你享有每週 stable 的更新節奏，無需手動更新標籤；固定特定版本則可讓你完全掌控升級時機。

## 建議策略 {#recommended-strategy}

這些管道的存在，是為了讓你將「取得最新修正」與「取得最新功能」脫鉤。一個安全且低維護成本的預設做法是：

1. **將生產環境固定在某個 stable 次要版本分支線**，例如 `ghcr.io/tuist/tuist:1.351`。該分支線僅接收回溯移植的修正，絕不包含新功能，因此日常升級風險較低。當你準備採用下一個次要版本時，再更新固定的版本。
2. **在 canary 或特定的 release-candidate 標籤上執行預備環境。** 預備環境能攔截原本會影響使用者的 regresions，且預備環境追蹤的版本越接近 `main`，就能越早發現問題。在目前 release-candidate 分支線上執行預備環境是個良好的折衷方案：它能浸泡即將在下週一成為 stable 的確切程式碼。
3. **查看[伺服器變更日誌](/changelog)以了解實際發布內容。** 每次 stable 推進都會在此公告，並列出合併的拉取請求。

若你希望新功能在成為 stable 後自動部署至生產環境，請將生產環境保持在 `:latest`。請注意，該標籤會在每週一早上推進，因此請據此安排你的部署時段。

## 回溯移植 {#backports}

任何時候都有兩條 stable 伺服器（及 Kura）分支線處於積極維護狀態：目前分支線會透過回溯移植拉取請求接收 regression 修正與安全性修正，而前一條分支線僅接收關鍵與安全性修正。較舊的分支線不會進行回溯移植；請升級至受維護的分支線以接收修正。當新分支線被推進為 stable 時，原本的「目前」分支線會變為「前一條」，而原本的「前一條」分支線則停止接收回溯移植。

回溯移植會按需切出為 `X.Y.(Z+1)` 修補版本。它們絕不會移動 `:latest`。
