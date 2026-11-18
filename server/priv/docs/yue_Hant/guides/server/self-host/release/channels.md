---
{
  "title": "發布渠道",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Tuist 如何透過 Canary、Release Candidate 及 Stable 渠道發布伺服器同 Kura Docker 映像，以及如何將你嘅部署鎖定喺可靠嘅版本線。"
}
---

# 發布渠道 {#release-channels}

Tuist 伺服器同 Kura 快取伺服器透過三個 GHCR 映像渠道發佈，各自提供唔同嘅穩定性保證。建議安裝 **stable** 版本，每週更新一次：佢唔會每次有新功能合併到 `main` 就自動升級，所以升級唔再意味著要吸收一批無關嘅變更。早期採用者仍然可以喺 **canary** 上運行每次提交嘅構建，而 **release candidate** 渠道則讓你喺新版本變為穩定之前預先試用。

伺服器同 Kura 都跟隨相同嘅每週發布節奏，並且與 <.localized_link href="/cli/release/channels">Tuist CLI 嘅發布時間表</.localized_link> 同步進行。

## 當前發布 {#live-release-status}

每個組件嘅當前發布版本顯示如下。請參閱 <.localized_link href="/guides/server/self-host/release/calendar">發布日曆</.localized_link> 以了解即將到來嘅發布窗口同最近嘅發布，包括修補程式同回溯移植。

<.release_status status={@release_status} components="server,kura" calendar_path="/guides/server/self-host/release/calendar" locale={@locale} />

## 渠道 {#the-channels}

| 渠道 | 版本格式 | 發布頻率 | 會移動 `:latest` 嗎？ |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N`（例如 `1.351.0-canary.5`） | 每次提交到 `main` | 否，需明確選擇加入 |
| Release candidate | `X.Y.0-rc.N`（例如 `1.351.0-rc.1`） | 每週一從 `main` 切割，試用約 1 週 | 否，需明確選擇加入 |
| Stable | `X.Y.Z`（例如 `1.350.2`、`1.351.0`） | 經過乾淨試用後，每週一提升 | **是** |

Canary 同 release-candidate 構建會作為 GitHub 預發布版本發佈。任何喺解析 `:latest` 時排除預發布版本嘅工具都會跳過它們，所以你只有喺明確請求時才會使用其中一個。

### Canary {#canary}

每次提交到 `main` 都會發佈一個 canary 映像。Canary 始終代表 **下一個未發布嘅次要版本**：一旦某個版本線被切割用於發布，`main` 就會推進到下一個次要版本（例如，從 `1.350.0-canary.42` 到 `1.351.0-canary.1`）。Canary 係適合用於模擬生產環境嘅暫存環境嘅渠道，它可以給你最早嘅回歸信號，或者喺修復到達穩定版本之前驗證你報告嘅修復是否按預期工作。

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

當一個次要版本準備好發佈時，其版本線會被凍結到受保護嘅 `releases/server-<major>.<minor>.x`（或 `releases/kura-<major>.<minor>.x`）分支上，並作為 `X.Y.0-rc.1` 發佈。該版本線處於功能凍結狀態；只有關鍵修復同回歸問題會被挑選進去，並且每個接受嘅修復都會迭代 release candidate 版本（`-rc.2`、`-rc.3` 等）。經過乾淨嘅試用期後，該版本線會喺下一個星期一提升為穩定版本。

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stable 係推薦嘅渠道，亦係所有文檔指向嘅版本。穩定嘅次要版本（`X.Y.0`）只有喺 release candidate 經過乾淨試用後才會發佈，並且當新功能合併到 `main` 時它 **不會** 推進。穩定版本線上嘅修補程式（`X.Y.1`、`X.Y.2` 等）只包含回溯移植嘅修復，絕不包含新功能。`:latest` 只有喺穩定版本提升時才會移動。

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## 星期一發布列車 {#the-monday-train}

每個星期一 UTC 時間 06:00，三個組件嘅發布列車會同步啟動：

1. **06:00 UTC** — 執行提升任務。每個任務都會提升最新嘅尚未穩定嘅 release-candidate 版本線（通常係上一個星期一切割嘅版本線），如果沒有則不執行任何操作。
2. **每次提升完成後** — release-candidate 任務會從 `main` 切割下一個版本線，因此新切割嘅版本線唔會喺同一次運行中被提升。

失敗嘅提升會阻擋切割：只會選擇高於最新穩定版本嘅最高 release-candidate 版本線，因此喺失敗基礎上切割下一個版本線會導致未發佈嘅版本線被擱置。下一個星期一会自動重試被擱置嘅版本線。

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

`:latest` 喺 `ghcr.io/tuist/tuist` 同 `ghcr.io/tuist/kura` 上都追蹤最新嘅穩定版本，僅喺星期一提升時移動。鎖定 `:latest` 讓你可以獲得每週穩定嘅發布節奏而無需更新標籤；鎖定特定版本則讓你完全控制升級時機。

## 推薦策略 {#recommended-strategy}

這些渠道嘅存在是為了讓你將「獲取最新修復」同「獲取最新功能」分開。一個安全且低工作量嘅默認策略係：

1. **將生產環境鎖定到一個穩定嘅次要版本線**，例如 `ghcr.io/tuist/tuist:1.351`。該版本線只接收回溯移植嘅修復，絕不包含新功能，因此日常升級保持低风险。當你準備採用下一個次要版本時再更新鎖定。
2. **喺 canary 或特定 release-candidate 標籤上運行預備環境。** 預備環境可以攔截原本會到達用戶手中嘅回歸問題，而且預備環境越貼近 `main`，你就越早發現問題。喺當前 release-candidate 版本線上運行預備環境係一個好好嘅折衷方案：它會試用即將喺下個星期一變成穩定版本嘅確切內容。
3. **查看[Server changelog](/changelog)以了解實際發佈咗乜嘢。** 每次穩定版本提升都會喺嗰度公佈，並列出成功合併嘅 pull request。

如果你希望新功能喺變成穩定版本後自動 rollout 到生產環境，就讓生產環境保持使用 `:latest`。只需注意標籤會喺每個星期一早上推進，因此請相應安排你嘅部署時間窗口。

## 回溯移植 {#backports}

任何時候都有兩條穩定嘅 server（同 Kura）版本線處於積極維護狀態：當前版本線會透過回溯移植 pull request 接收回歸修復同安全修復，而上一條版本線只接收關鍵同安全修復。更舊嘅版本線不會進行回溯移植；請升級到受維護嘅版本線以接收修復。當一條新版本線被提升為穩定版本時，原本嘅「當前」版本線會變成「上一條」，而原本嘅「上一條」版本線則停止接收回溯移植。

回溯移植會按需切割為 `X.Y.(Z+1)` 修補版本。它們永遠不會移動 `:latest`。
