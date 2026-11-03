---
{
  "title": "發布管道",
  "titleTemplate": ":title | 自行託管 | Server | 指南 | Tuist",
  "description": "Tuist 如何透過 Canary、Release Candidate 與 Stable 管道發布伺服器與 Kura Docker 映像檔，以及如何將你的部署固定在你信賴的發行系列。"
}
---

# 發布管道 {#release-channels}

Tuist 伺服器與 Kura 快取伺服器透過三個 GHCR 映像檔管道提供，各自具備不同的穩定性保證。建議安裝 **stable** 頻道，每週更新一次：它不會在每次功能合併至 `main` 時就前進，因此升級不再意味著吸收一批不相關的變更。早期採用者仍可在 **canary** 上執行每次提交的建置，而 **release candidate** 頻道則讓你在版本穩定前先進行預先驗證。

伺服器與 Kura 都搭乘相同的每週列車，並與 [Tuist CLI 的發布時程](/en/cli/release-channels)同步推進。

## 各管道 {#the-channels}

| 管道 | 版本格式 | 頻率 | 會移動 `:latest`？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `1.351.0-canary.5`） | 每次提交至 `main` | 否，需明確選擇 |
| Release candidate | `X.Y.0-rc.N`（例如 `1.351.0-rc.1`） | 每週一從 `main` 切出，預先驗證約 1 週 | 否，需明確選擇 |
| Stable | `X.Y.Z`（例如 `1.350.2`、`1.351.0`） | 經過乾淨的預先驗證後，於每週一提升 | **是** |

Canary 與 release-candidate 建置會以 GitHub 預發布形式發布。任何在解析 `:latest` 時排除預發布的工具都會略過它們，因此你只有明確指定時才會使用其中一個。

### Canary {#canary}

每次提交至 `main` 都會發布一個 canary 映像檔。Canary 永遠代表**下一個尚未發布的次要版本**：一旦為發布切出一條分支，`main` 就會前進到下一個次要版本（例如從 `1.350.0-canary.42` 到 `1.351.0-canary.1`）。若你需要一個能鏡像生產環境、盡早發現回歸問題，或在你回報的修復進入 stable 之前驗證其行為是否符合預期，Canary 是合適的管道。

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

當某個次要版本準備好交付時，其分支會被凍結到受保護的 `releases/server-<major>.<minor>.x`（或 `releases/kura-<major>.<minor>.x`）分支，並以 `X.Y.0-rc.1` 發布。該分支處於功能凍結狀態；只會將關鍵修復與回歸修補 cherry-pick 上去，且每接受一個修復就會迭代 release candidate（`-rc.2`、`-rc.3`，依此類推）。在預先驗證期順利結束後，該分支將於下週一提升為 stable。

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stable 是建議使用的管道，也是所有文件指向的管道。只有在 release candidate 經過乾淨的預先驗證後，才會發布穩定的次要版本（`X.Y.0`），而且當新功能合併至 `main` 時，它**不會**前進。穩定分支上的修補版本（`X.Y.1`、`X.Y.2`，依此類推）僅包含回溯移植的修復，絕不包含新功能。`:latest` 僅在穩定版提升時才會移動。

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## 週一列車 {#the-monday-train}

每週一 UTC 06:00，三個元件的發布列車會同步觸發：

1. **UTC 06:00** — 執行提升作業。每個作業會提升最新且尚未成為 stable 的 release-candidate 分支（通常是上週一切出的分支）；若沒有符合條件的分支，則不執行任何動作。
2. **每次提升完成後** — release-candidate 作業會從 `main` 切出下一條分支，因此剛切出的分支不會在同一輪中被提升。

若提升失敗，切出動作會被延後：系統只會挑選高於最新 stable 的最高 release-candidate 分支，因此在失敗之上再切出下一條分支會讓未交付的分支孤立。下週一會自動重試被延後的分支。

## 固定管道 {#pinning-a-channel}

在你的部署清單、Helm 值或 Docker Compose 檔案中固定你想要的特定標籤。以下以 Helm chart 為例：

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

`:latest` 在 `ghcr.io/tuist/tuist` 與 `ghcr.io/tuist/kura` 上都追蹤最新的 stable 版本，僅在週一提升時移動。固定 `:latest` 可讓你享有每週穩定的節奏，無需手動更新標籤；固定特定版本則可讓你完全掌控升級時機。

## 建議策略 {#recommended-strategy}

這些管道的存在，是為了讓你將「取得最新修復」與「取得最新功能」解耦。一個安全且低維護成本的預設做法是：

1. **將生產環境固定在一個穩定的次要版本分支**，例如 `ghcr.io/tuist/tuist:1.351`。該分支只會接收回溯移植的修復，絕不會加入新功能，因此日常升級風險較低。當你準備採用下一個次要版本時，再更新固定的版本。
2. **在 canary 或特定的 release-candidate 標籤上執行預備環境。** 預備環境能攔截原本會影響使用者的回歸問題，且預備環境越接近 `main`，你就能越早發現問題。在目前 release-candidate 分支上運行預備環境是一個良好的折衷方案：它能預先驗證下週一將成為 stable 的確切內容。
3. **查看[伺服器變更日誌](/changelog)以了解實際交付的內容。** 每次穩定版提升都會在此公告，並附上納入的拉取請求清單。

若你希望新功能在成為 stable 後自動推播至生產環境，請將生產環境保持在 `:latest`。請注意，該標籤每週一早上會推進，因此請相應安排你的部署時段。

## 回溯移植 {#backports}

任何時候都會積極維護兩條穩定的伺服器（及 Kura）分支：目前分支會透過回溯移植拉取請求接收回歸修復與安全性修復，而前一個分支僅接收關鍵與安全性修復。較舊的分支不會進行回溯移植；請升級至受維護的分支以取得修復。當新分支被提升為 stable 時，原本的「目前」分支會變為「前一個」，而原本的「前一個」分支則停止接收回溯移植。

回溯移植會依需求切出為 `X.Y.(Z+1)` 修補版本。它們絕不會移動 `:latest`。
