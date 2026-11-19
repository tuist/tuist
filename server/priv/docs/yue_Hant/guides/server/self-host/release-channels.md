---
{
  "title": "發布渠道",
  "titleTemplate": ":title | 自行託管 | 伺服器 | 指南 | Tuist",
  "description": "Tuist 如何透過 Canary、候選版本及穩定渠道發佈伺服器與 Kura Docker 映像，以及如何將你的部署鎖定在可信赖的分支上。"
}
---

# 發布渠道 {#release-channels}

Tuist 伺服器同 Kura 快取伺服器透過三個 GHCR 映像渠道發布，各自提供唔同嘅穩定性保證。建議安裝 **stable** 渠道，每週更新一次：佢唔會每次有功能合併到 `main` 就升級，所以升級唔再等於要吸收一批無關嘅變更。早期採用者仍然可以喺 **canary** 渠道運行每次提交嘅構建，而 **release candidate** 渠道則讓你在某條版本線變成 stable 之前先進行預熱測試。

伺服器同 Kura 都跟隨同一班每週列車，並且與 [Tuist CLI 的發布時間表](/en/cli/release-channels) 同步推進。

## 渠道 {#the-channels}

| 渠道 | 版本格式 | 頻率 | 會移動 `:latest` 嗎？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `1.351.0-canary.5`） | 每次提交到 `main` | 否，需明確選擇加入 |
| Release candidate | `X.Y.0-rc.N`（例如 `1.351.0-rc.1`） | 每週一從 `main` 切出，預熱約 1 週 | 否，需明確選擇加入 |
| Stable | `X.Y.Z`（例如 `1.350.2`、`1.351.0`） | 經過乾淨預熱後，於每週一提升 | **是** |

Canary 同 release-candidate 構建會以 GitHub prerelease 形式發布。任何喺解析 `:latest` 時排除 prerelease 嘅工具都會跳過它們，所以你只有喺明確請求時才會用到其中一個。

### Canary {#canary}

每次提交到 `main` 都會發布一個 canary 映像。Canary 始終代表 **下一個未發布嘅次要版本**：一旦某條版本線被切出用於發布，`main` 就會推進到下一個次要版本（例如由 `1.350.0-canary.42` 變為 `1.351.0-canary.1`）。如果你需要一個模擬生產環境嘅 staging 環境，以便最早收到回歸問題嘅信號，或者想驗證你報告嘅修復在進入 stable 之前行為符合預期，Canary 就係合適嘅渠道。

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

當某個次要版本準備好發布時，其版本線會被凍結到受保護嘅 `releases/server-<major>.<minor>.x`（或 `releases/kura-<major>.<minor>.x`）分支，並以 `X.Y.0-rc.1` 形式發布。該版本線處於功能凍結狀態；只會揀選關鍵修復同回歸修復，每個被接受嘅修復都會迭代 release candidate 版本（`-rc.2`、`-rc.3` 等）。預熱期順利結束後，該版本線會於下一個星期一提升為 stable。

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stable 係推薦渠道，亦係所有文檔指向嘅渠道。只有當 release candidate 順利完成預熱後，才會發布 stable 次要版本（`X.Y.0`），而且當新功能合併到 `main` 時，它並 **不會** 推進。Stable 版本線上嘅補丁版本（`X.Y.1`、`X.Y.2` 等）只包含回溯修復，絕不包含新功能。`:latest` 只會在 stable 提升時移動。

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## 星期一列車 {#the-monday-train}

每逢星期一 UTC 06:00，三個組件嘅發布列車會同步啟動：

1. **UTC 06:00** — 執行提升作業。每個作業會提升最新仍未成為 stable 嘅 release-candidate 版本線（通常係上星期一切出嘅版本線）；如果沒有則不執行任何操作。
2. **每次提升完成後** — release-candidate 作業會從 `main` 切出下一條版本線，因此剛切出嘅版本線唔會喺同一輪運行中被提升。

如果提升失敗，切出版本線嘅動作會被擱置：系統只會揀選高於最新 stable 版本嘅最高 release-candidate 版本線，因此如果在失敗基礎上繼續切出下一條版本線，會令未能發布嘅版本線孤立無援。下一個星期一會自動重試被擱置嘅版本線。

## 固定渠道 {#pinning-a-channel}

喺你嘅部署清單、Helm 值或 Docker Compose 文件中固定你想要嘅特定標籤。例如，使用 Helm chart：

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

`:latest` 喺 `ghcr.io/tuist/tuist` 同 `ghcr.io/tuist/kura` 上都會追蹤最新嘅 stable 版本，只喺星期一提升時移動。固定 `:latest` 讓你可以享受每週 stable 嘅節奏而無需更新標籤；固定特定版本則讓你完全控制升級時機。

## 推薦策略 {#recommended-strategy}

設置呢啲渠道係為了讓你將「獲取最新修復」同「獲取最新功能」分開。一個安全且低工作量嘅默認做法係：

1. **將生產環境固定喺一個 stable 次要版本線**，例如 `ghcr.io/tuist/tuist:1.351`。該版本線只接收回溯修復，絕無新功能，因此日常升級風險較低。當你準備採用下一個次要版本時，再更新固定版本。
2. **喺 canary 或特定 release-candidate 標籤上運行 staging 環境。** Staging 可以攔截否則會到達用戶手中嘅回歸問題，而且 staging 追蹤嘅版本越接近 `main`，你就越早發現問題。喺當前 release-candidate 版本線上運行 staging 環境係一個不錯嘅折中方案：它會預熱即將喺下一個星期一變成 stable 嘅確切內容。
3. **參閱 [伺服器變更日誌](/changelog) 了解實際發布咗乜嘢。** 每次 stable 提升都會喺嗰度公告，並列出已合併嘅拉取請求。

如果你希望新功能一旦變成 stable 就自動發布到生產環境，可以將生產環境保持喺 `:latest`。請注意標籤會喺每個星期一早上推進，因此請相應安排你嘅部署時間窗口。

## 回溯修復 {#backports}

任何時候都有兩條 stable 伺服器（同 Kura）版本線處於積極維護狀態：當前版本線會以回溯拉取請求嘅形式接收回歸問題修復同安全修復，而上一條版本線只接收關鍵性同安全修復。更舊嘅版本線唔會進行回溯修復；請升級到受維護嘅版本線以獲取修復。當一條新版本線被提升為 stable 時，原本嘅「當前」版本線會變成「上一條」，而原本嘅「上一條」版本線則停止接收回溯修復。

回溯修復會按需切出為 `X.Y.(Z+1)` 補丁版本。它們永遠唔會移動 `:latest`。
