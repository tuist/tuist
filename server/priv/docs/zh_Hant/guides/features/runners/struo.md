---
{
  "title": "Struo 遠端執行",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "在 Tuist 的 Linux 遠端執行工作節點上，執行符合條件的 Struo 圖形指令動作。"
}
---
# Struo 遠端執行 {#struo-remote-execution}

<a id="once-remote-execution"></a>

共用快取可避免重複其他機器已完成的作業。遠端執行也會將符合條件的快取未命中移出你的電腦：Struo 會在 Tuist 的一次性 Linux 工作節點上排程圖形指令動作，並透過相同的專案快取擷取其輸出。

> [!NOTE]
> 遠端執行目前僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)以申請帳戶存取權限。

> [!IMPORTANT]
> **需求**
>
> - 已啟用遠端執行且具備可用執行容量的 Tuist 帳戶。
> - 支援 Tuist 遠端執行的 Struo 版本。
> - 相容的伺服器，需公告工作節點映像、快取端點、並行度以及絕對執行目錄。省略目錄的伺服器與目前的 Struo 用戶端不相容；Struo 會在上傳工作前停止。
> - 可在公告的工作節點映像內的 `linux/amd64` 上執行的指令與工具鏈。

這會執行圖形動作，而非整個 CI 工作。設定 Struo 並不會安裝 GitHub 或 GitLab 工作流程協調器。

## 設定 {#setup}

完成<.localized_link href="/guides/get-started/struo-project">開始使用 Struo</.localized_link>。為快取與執行選取相同的 Tuist 提供者，並鎖定服務所公告的工作節點映像：

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"
execution_image = "sha-REPLACE_WITH_THE_IMAGE_TAG"

[infrastructure.cache]
provider = "tuist"

[infrastructure.execution]
provider = "tuist"
```

使用具備讀寫專案快取權限的憑證進行驗證，然後請求遠端執行：

```bash
struo build --remote MyTarget
```

將目標與映像標籤替換為你自己的值。Struo 會在上傳工作前檢查公告的映像、執行目錄、快取目的地與帳戶容量。快取與執行必須指向同一個專案。

## 為工作節點準備動作 {#prepare-actions-for-workers}

- 宣告輸入與輸出。輸出必須保留在動作的作業目錄之下。
- 在工作節點映像內解析工具，而非在發起電腦的絕對路徑上解析。
- 使用可安全重複執行的動作：工作節點失敗或服務重新啟動可能會導致再次執行。
- 將逾時控制在服務的十分鐘動作限制內。不支援的需求（包括網路拒絕）會失敗，而不會在本地靜默執行。

Struo 會遵循帳戶公告的動作並行度，並在服務佇列滿載時退避。變更映像會區隔建置設定與快取結果，防止在不相容的工作節點映像之間重複使用。

## 檢視遠端執行 {#inspect-remote-execution}

專案側邊欄有一個**遠端執行**頁面。其**分析**卡片會顯示所選期間的執行次數與總執行時間，詳見<.localized_link href="/guides/features/cache/bazel-cache#running-actions-and-usage">執行動作與用量</.localized_link>。在 Struo 2.19.0 之後的版本中，每個遠端動作都會標示其所屬的 Struo 執行，因此該頁面也會繪製佇列與執行時間圖表，並列出各執行的遠端動作、結果與耗時，優先顯示正在執行的執行。點擊執行會在**建置執行**中開啟其頁面。來自較舊用戶端的執行，以及由遠端快取回應的動作，不會計入其中。目前正在執行與排隊中的遠端動作可透過`get_remote_execution_activity` MCP 工具及其 REST 端點取得。兩者皆來自執行服務，而非工作節點通道。

參閱[Struo 遠端執行指南](https://struo.run/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers)以了解佇列、驗證刷新與快取端點覆寫。依照<.localized_link href="/guides/features/build-insights/struo">Struo 建置洞察</.localized_link>檢視產生的執行。
