---
{
  "title": "發布渠道",
  "titleTemplate": ":title | 自行託管 | 伺服器 | 指南 | Tuist",
  "description": "Tuist 如何透過 Canary、Release Candidate 及穩定渠道發佈伺服器同 Kura Docker 映像，以及如何將你嘅部署鎖定喺可靠嘅版本線。"
}
---

# 發布渠道 {#release-channels}

Tuist 伺服器同 Kura 快取伺服器透過三個 GHCR 映像渠道發布，各自提供唔同嘅穩定性保證。建議安裝 **stable** 渠道，每週更新一次：佢唔會每次有功能合併到 `main` 就推進，所以升級唔再意味住要吸收一批無關嘅變更。早期採用者仍然可以喺 **canary** 渠道運行每次提交嘅構建，而 **release candidate** 渠道則讓你喺即將成為穩定版之前先行試用該版本線。

伺服器同 Kura 都跟隨相同嘅每週發布節奏，並且同 [Tuist CLI 嘅發布時間表](/en/cli/release-channels) 同步進行。

## 渠道 {#the-channels}

| 渠道 | 版本格式 | 頻率 | 會推進 `:latest` 嗎？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `1.351.0-canary.5`） | 每次提交到 `main` | 否，需明確選擇 |
| Release candidate | `X.Y.0-rc.N`（例如 `1.351.0-rc.1`） | 每週一從 `main` 切出，試用約 1 週 | 否，需明確選擇 |
| Stable | `X.Y.Z`（例如 `1.350.2`、`1.351.0`） | 經過乾淨試用後，每週一推進 | **是** |

Canary 同 release-candidate 構建會以 GitHub 預發布形式發布。任何喺解析 `:latest` 時排除預發布版本嘅工具都會跳過它們，因此你只有喺明確請求時才會使用其中一個。

### Canary {#canary}

每次提交到 `main` 都會發布一個 canary 映像。Canary 始終代表 **下一個未發布嘅次版本**：一旦某個版本線被切出用於發布，`main` 就會推進到下一個次版本（例如，從 `1.350.0-canary.42` 到 `1.351.0-canary.1`）。Canary 係適合用於模擬生產環境嘅暫存環境嘅渠道，可讓你最早收到回歸問題嘅信號，或者喺修復到達穩定版之前驗證你報告嘅修復是否按預期運作。

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

當一個次版本準備好發布時，其版本線會被凍結到受保護嘅 `releases/server-<major>.<minor>.x`（或 `releases/kura-<major>.<minor>.x`）分支，並以 `X.Y.0-rc.1` 形式發布。該版本線處於功能凍結狀態；只有關鍵修復同回歸問題會被揀選合併到其中，每個被接受嘅修復都會迭代 release candidate 版本（`-rc.2`、`-rc.3` 等）。經過乾淨嘅試用期後，該版本線會喺下一個星期一推進為穩定版。

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stable 係建議使用嘅渠道，亦係所有文件指向嘅渠道。穩定版次版本（`X.Y.0`）只有喺 release candidate 經過乾淨試用後才會發布，並且當新功能合併到 `main` 時，它並**不會**推進。穩定版本線上嘅補丁版本（`X.Y.1`、`X.Y.2` 等）只包含回溯修復，絕不包含新功能。`:latest` 只有喺穩定版推進時才會移動。

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## 星期一發布列車 {#the-monday-train}

每個星期一 UTC 時間 06:00，三個組件嘅發布列車會同步啟動：

1. **UTC 時間 06:00** — 推進任務運行。每個任務會推進最新嘅尚未成為穩定版嘅 release-candidate 版本線（通常係上個星期一切出嘅版本線），如果沒有則不執行任何操作。
2. **每次推進完成後** — release-candidate 任務會從 `main` 切出下一個版本線，因此新切出嘅版本線唔會喺同一次運行中被推進。

如果推進失敗，切出版本線嘅操作會被擱置：系統只會揀選高於最新穩定版嘅最高 release-candidate 版本線，因此如果喺失敗基礎上切出下一個版本線，會導致未能發布嘅版本線被孤立。下一個星期一会自動重試被擱置嘅版本線。

## 鎖定渠道 {#pinning-a-channel}

喺你嘅部署清單、Helm 值或 Docker Compose 文件中鎖定你想要嘅特定標籤。例如，使用 Helm chart：

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

`:latest` 喺 `ghcr.io/tuist/tuist` 同 `ghcr.io/tuist/kura` 上都追蹤最新嘅穩定版，僅喺星期一推進時移動。鎖定 `:latest` 可讓你獲得每週穩定版嘅節奏而無需更新標籤；鎖定特定版本則可讓你完全控制升級時機。

## 建議策略 {#recommended-strategy}

設立呢啲渠道係為了讓你可以將「獲取最新修復」同「獲取最新功能」分開。一個安全且低工作量嘅默認策略係：

1. **將生產環境鎖定到一個穩定嘅次版本線**，例如 `ghcr.io/tuist/tuist:1.351`。該版本線只接收回溯修復，絕不包含新功能，因此日常升級保持低風險。當你準備採用下一個次版本時，再更新鎖定版本。
2. **喺 canary 或特定 release-candidate 標籤上運行暫存環境。** 暫存環境可以捕捉否則會影響用戶嘅回歸問題，而且暫存環境越接近 `main`，你就越早發現它們。喺當前 release-candidate 版本線上運行暫存環境係一個良好嘅折中方案：它會試用即將喺下一個星期一成為穩定版嘅確切內容。
3. **查看 [伺服器變更日誌](/changelog) 以了解實際發布嘅內容。** 每次穩定版推進都會喺那裡公告，並列出已合併嘅拉取請求。

如果你希望新功能喺成為穩定版後自動推出到生產環境，可以將生產環境保持喺 `:latest`。請注意標籤會喺每個星期一早上推進，因此請相應安排你嘅部署時間窗口。

## 回溯修復 {#backports}

任何時候都有兩條穩定嘅伺服器（同 Kura）版本線處於積極維護狀態：當前版本線會以回溯拉取請求嘅形式接收回歸問題修復同安全修復，而上一個版本線只接收關鍵同安全修復。較舊嘅版本線唔會進行回溯修復；請升級到受維護嘅版本線以接收修復。當一條新版本線被推進為穩定版時，原本嘅當前版本線會變成「上一個」，而原本嘅「上一個」版本線則停止接收回溯修復。

回溯修復會按需切出為 `X.Y.(Z+1)` 補丁版本。它們永遠唔會移動 `:latest`。
