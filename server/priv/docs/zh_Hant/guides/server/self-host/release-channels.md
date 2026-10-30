---
{
  "title": "發布管道",
  "titleTemplate": ":title | 自行託管 | Server | 指南 | Tuist",
  "description": "Tuist 如何在 Canary、Release Candidate 與穩定版管道中交付 Server 與 Kura Docker 映像檔，以及如何將你的部署固定在你信賴的分支上。"
}
---

# 發布管道 {#release-channels}

Tuist 伺服器與 Kura 快取伺服器透過三個 GHCR 映像檔管道發布，各自提供不同的穩定性保證。建議安裝 **stable** 頻道，每週更新一次：它不會在每次功能合併至 `main` 時就推進，因此升級不再意味著吸收一批無關的變更。早期採用者仍可在 **canary** 上執行每次提交的建置，而 **release candidate** 頻道則讓你在版本線成為穩定版之前先行試用。

伺服器與 Kura 都搭乘相同的每週列車，並與 [Tuist CLI 的發布時程](/en/cli/release-channels) 同步推進。

## 各管道 {#the-channels}

| 管道 | 版本格式 | 頻率 | 會推進 `:latest` 嗎？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `1.351.0-canary.5`） | 每次提交至 `main` | 否，需明確選擇 |
| Release candidate | `X.Y.0-rc.N`（例如 `1.351.0-rc.1`） | 每週一從 `main` 切出，試用約 1 週 | 否，需明確選擇 |
| Stable | `X.Y.Z`（例如 `1.350.2`、`1.351.0`） | 經過乾淨試用後，於每週一推進 | **是** |

Canary 與 release-candidate 建置會以 GitHub 預發布形式發布。任何在解析 `:latest` 時排除預發布版本的工具都會略過它們，因此只有在你明確指定時才會使用其中任一版本。

### Canary {#canary}

每次提交至 `main` 都會發布一個 canary 映像檔。Canary 始終代表 **下一個尚未發布的次要版本**：一旦為發布切出版本線，`main` 就會推進到下一個次要版本（例如從 `1.350.0-canary.42` 到 `1.351.0-canary.1`）。若你需要一個鏡像生產環境的暫存環境，以便最早收到回歸問題的訊號，或想在修復進入穩定版之前驗證你回報的修正是否符合預期，Canary 就是合適的管道。

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

當某個次要版本準備好交付時，其版本線會被凍結到受保護的 `releases/server-<major>.<minor>.x`（或 `releases/kura-<major>.<minor>.x`）分支，並以 `X.Y.0-rc.1` 的形式發布。該版本線處於功能凍結狀態；只會挑選關鍵修復與回歸修補，且每個被接受的修復都會迭代 release candidate 版本（`-rc.2`、`-rc.3` 等）。在試用期順利結束後，該版本線將於隔週一推進為穩定版。

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stable 是建議使用的管道，也是所有文件指向的版本。只有在 release candidate 經過乾淨試用後，才會發布穩定版的次要版本（`X.Y.0`），而且當新功能合併至 `main` 時，它 **不會** 推進。穩定版本線上的修補版本（`X.Y.1`、`X.Y.2` 等）僅包含回溯移植的修復，絕不包含新功能。`:latest` 只會在穩定版推進時移動。

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## 週一列車 {#the-monday-train}

每週一 UTC 06:00，三個元件的發布列車會同步觸發：

1. **06:00 UTC** — 執行推進作業。每個作業會推進最新且尚未成為穩定版的 release-candidate 版本線（通常是前一個週一切出的版本線）；若沒有候選版本，則不執行任何動作。
2. **每次推進完成後** — release-candidate 作業會從 `main` 切出下一個版本線，因此剛切出的版本線不會在同一輪中就被推進。

若推進失敗，切出動作會被擱置：系統只會挑選高於最新穩定版的最高 release-candidate 版本線，因此在失敗之上再切出新版本線會讓未交付的版本線孤立。下個週一會自動重試被擱置的版本線。

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

`:latest` 在 `ghcr.io/tuist/tuist` 與 `ghcr.io/tuist/kura` 上都會追蹤最新的穩定版，且僅在週一推進時移動。固定 `:latest` 可讓你享有每週穩定版的節奏，無需手動更新標籤；固定特定版本則可讓你完全掌控升級時機。

## 建議策略 {#recommended-strategy}

這些管道的存在，是為了讓你將「取得最新修復」與「取得最新功能」解耦。一個安全且低維護成本的預設做法是：

1. **將生產環境固定在穩定的次要版本線**，例如 `ghcr.io/tuist/tuist:1.351`。該版本線只會接收回溯移植的修復，絕不包含新功能，因此日常升級風險較低。當你準備採用下一個次要版本時，再更新固定的版本。
2. **在 canary 或特定的 release-candidate 標籤上執行暫存環境。** 暫存環境能攔截原本會影響使用者的回歸問題，而且暫存環境越接近 `main`，你就能越早發現問題。在目前的 release-candidate 版本線上執行暫存環境是個良好的折衷方案：它會完整試用即將在下個週一成為穩定版的相同內容。
3. **查看 [伺服器變更紀錄](/changelog) 以了解實際交付的內容。** 每次穩定版推進都會在此公告，並列出納入的拉取請求。

如果你希望新功能在成為穩定版後自動部署至生產環境，請將生產環境保持在 `:latest`。請注意，該標籤會在每週一上午推進，因此請據此安排你的部署時段。

## 回溯移植 {#backports}

任何時候都會積極維護兩條穩定的伺服器（與 Kura）版本線：目前版本線會透過回溯移植的拉取請求接收回歸修復與安全性修復，而前一條版本線僅接收關鍵與安全性修復。較舊的版本線不會進行回溯移植；請升級至受維護的版本線以取得修復。當新版本線被推進為穩定版時，原本的「目前」版本線會變成「前一條」，而原本的「前一條」版本線則會停止接收回溯移植。

回溯移植會按需切出為 `X.Y.(Z+1)` 修補版本。它們絕不會移動 `:latest`。
