---
{
  "title": "發布渠道",
  "titleTemplate": ":title | 自行託管 | Server | 指南 | Tuist",
  "description": "了解 Tuist 如何透過 Canary、候選版本及穩定渠道發佈 Server 同 Kura Docker 映像，以及點樣將你嘅部署鎖定喺可靠嘅版本線。"
}
---

# 發布渠道 {#release-channels}

Tuist 伺服器同 Kura 快取伺服器透過三個 GHCR 映像渠道發布，每個渠道提供唔同嘅穩定性保證。建議安裝 **stable**，每週更新一次：佢唔會每次有功能合併到 `main` 就推進，所以升級唔再需要吸收一批無關嘅變更。早期採用者仍然可以喺 **canary** 上運行每次提交嘅構建，而 **release candidate** 渠道則讓你喺即將成為 stable 之前預先測試該分支。

伺服器同 Kura 都跟隨同一個每週發布節奏，並與 <.localized_link href="/cli/release/channels">Tuist CLI 嘅發布時間表</.localized_link> 同步執行。

## 當前版本 {#live-release-status}

以下顯示每個組件嘅當前版本。請參閱 <.localized_link href="/guides/server/self-host/release/calendar">發布日曆</.localized_link> 以了解即將到來嘅發布窗口同最近嘅發布，包括補丁同回溯修補。

<.release_status status={@release_status} components="server,kura" calendar_path="/guides/server/self-host/release/calendar" locale={@locale} />

## 渠道 {#the-channels}

| 渠道 | 版本格式 | 頻率 | 會推進 `:latest` 嗎？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `1.351.0-canary.5`） | 每次提交到 `main` | 否，需明確選擇加入 |
| Release candidate | `X.Y.0-rc.N`（例如 `1.351.0-rc.1`） | 每週一從 `main` 切割，測試約 1 週 | 否，需明確選擇加入 |
| Stable | `X.Y.Z`（例如 `1.350.2`、`1.351.0`） | 經過乾淨測試後，每週一推進 | **是** |

Canary 同 release-candidate 構建會以 GitHub 預發布形式發布。任何喺解析 `:latest` 時排除預發布嘅工具都會跳過它們，因此你只有喺明確請求時才會使用其中一個。

### Canary {#canary}

每次提交到 `main` 都會發布一個 canary 映像。Canary 始終代表 **下一個未發布嘅次要版本**：一旦某個分支被切割用於發布，`main` 就會推進到下一個次要版本（例如，從 `1.350.0-canary.42` 到 `1.351.0-canary.1`）。Canary 係適合用於模擬生產環境嘅暫存環境，可以最早發現回歸問題，或者喺修復到達 stable 之前驗證你報告嘅修復是否符合預期。

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

當一個次要版本準備好發布時，其分支會被凍結到受保護嘅 `releases/server-<major>.<minor>.x`（或 `releases/kura-<major>.<minor>.x`）分支上，並以 `X.Y.0-rc.1` 形式發布。該分支功能凍結；只有關鍵修復同回歸問題會被 cherry-pick 到上面，每個接受嘅修復都會迭代 release candidate（`-rc.2`、`-rc.3` 等）。經過乾淨嘅測試期後，該分支會喺下一個星期一推進到 stable。

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stable 係建議渠道，亦係所有文檔指向嘅渠道。只有當 release candidate 經過乾淨測試後，stable 次要版本（`X.Y.0`）才會發布，並且當新功能合併到 `main` 時，它 **不會** 推進。stable 分支上嘅補丁（`X.Y.1`、`X.Y.2` 等）只包含回溯修補，絕不包含新功能。`:latest` 只會在 stable 推進時移動。

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## 星期一列車 {#the-monday-train}

每週一 UTC 時間 06:00，三個組件嘅發布列車會同步執行：

1. **06:00 UTC** — 推進任務運行。每個任務會推進最新嘅尚未成為 stable 嘅 release-candidate 分支（通常係上一個星期一切割嘅分支），如果沒有則不做任何事。
2. **每次推進完成後** — release-candidate 任務會從 `main` 切割下一個分支，因此新切割嘅分支唔會喺同一輪中推進。

失敗嘅推進會延遲切割：只會選擇高於最新 stable 嘅最高 release-candidate 分支，因此喺失敗基礎上切割下一個分支會令未發布嘅分支孤立。下一個星期一会自動重試被延遲嘅分支。

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

`:latest` 喺 `ghcr.io/tuist/tuist` 同 `ghcr.io/tuist/kura` 上都追蹤最新嘅 stable，只喺星期一推進時移動。鎖定 `:latest` 讓你無需更新標籤即可獲得每週 stable 節奏；鎖定特定版本則讓你完全控制升級時機。

## 建議策略 {#recommended-strategy}

渠道嘅存在讓你將「獲取最新修復」同「獲取最新功能」分開。一個安全、低工作量嘅默認策略係：

1. **將生產環境鎖定到一個 stable 次要分支**，例如 `ghcr.io/tuist/tuist:1.351`。該分支只接收回溯修補，絕無新功能，因此日常升級保持低風險。當你準備採用下一個次要版本時，再更新鎖定。
2. **喺 canary 或特定 release-candidate 標籤上運行 staging 環境。** Staging 可以攔截原本會到達用戶手上嘅回歸問題，而 staging 追蹤 `main` 越貼近，你就越早發現問題。喺當前 release-candidate 分支上運行 staging 環境係一個好嘅折衷方案：它會測試將喺下個星期一變成 stable 嘅確切代碼。
3. **查看[Server changelog](/changelog)以了解實際發布咗乜嘢。** 每次 stable 推進都會喺嗰度公告，並列出被合併嘅 pull request。

如果你希望新功能一旦變成 stable 就自動部署到生產環境，請將生產環境保持在 `:latest`。只需注意標籤會喺每週一早上推進，因此請相應安排你嘅部署窗口。

## 回溯修補 {#backports}

任何時候都有兩個 stable server（同 Kura）分支處於積極維護狀態：當前分支接受作為回溯修補 pull request 嘅回歸問題和安全修復，而上一個分支只接受關鍵和安全修復。更舊嘅分支不會進行回溯修補；請升級到受維護嘅分支以接收修復。當新分支被推進到 stable 時，原來嘅「當前」分支會變成「上一個」，而原來嘅「上一個」分支則停止接收回溯修補。

回溯修補會按需切割為 `X.Y.(Z+1)` 補丁版本發布。它們永遠不會移動 `:latest`。
