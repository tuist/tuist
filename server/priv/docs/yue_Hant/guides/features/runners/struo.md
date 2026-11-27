---
{
  "title": "Struo 遠端執行",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "喺 Tuist 嘅 Linux 遠端執行工作節點上，執行符合資格嘅 Struo 圖表指令動作。"
}
---
# Struo 遙距執行 {#struo-remote-execution}

<a id="once-remote-execution"></a>

共用快取可以避免重複其他機器已經完成的工作。遙距執行亦會將符合條件的快取未命中工作從你的電腦移走：Struo 會在 Tuist 的一次性 Linux 工作節點上排程圖形指令動作，並透過同一個專案快取擷取其輸出。

> [!NOTE]
> 遙距執行目前只限邀請使用。[聯絡我們](mailto:contact@tuist.dev)以申請帳戶存取權限。

> [!IMPORTANT]
> **要求**
>
> - 已啟用遙距執行並有可用執行容量的 Tuist 帳戶。
> - 支援 Tuist 遙距執行的 Struo 版本。
> - 相容的伺服器，需宣傳工作節點映像、快取端點、並行度及絕對執行目錄。省略目錄的伺服器與目前的 Struo 用戶端不相容；Struo 會在上傳工作前停止。
> - 可在宣傳的工作節點映像內的 `linux/amd64` 上運行的指令和工具鏈。

這會執行圖形動作，而非整個 CI 工作。設定 Struo 並不會安裝 GitHub 或 GitLab 工作流程協調。

## 設定 {#setup}

完成<.localized_link href="/guides/get-started/struo-project">開始使用 Struo</.localized_link>。為快取和執行選擇相同的 Tuist 提供者，並鎖定服務所宣傳的工作節點映像：

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

使用可讀寫專案快取的憑證進行驗證，然後請求遙距執行：

```bash
struo build --remote MyTarget
```

將目標和映像標籤替換為你自己的。Struo 會在上傳工作前檢查宣傳的映像、執行目錄、快取目的地和帳戶容量。快取和執行必須指向同一個專案。

## 為工作節點準備動作 {#prepare-actions-for-workers}

- 宣告輸入和輸出。輸出必須保留在動作的作業目錄之下。
- 在工作節點映像內解析工具，而非在發起電腦的絕對路徑上。
- 使用可安全重複執行的動作：工作節點失敗或服務重新啟動可能會導致再次執行。
- 將逾時保持在服務的十分鐘動作限制內。不支援的要求（包括網絡拒絕）會失敗，而不會靜默地在本地運行。

Struo 會遵守帳戶宣傳的動作並行度，並在服務佇列滿時退避。更改映像會分隔建置設定和快取結果，防止在不相容的工作節點映像之間重用。

## 檢視遙距執行 {#inspect-remote-execution}

專案側邊欄有一個**遙距執行**頁面。其**分析**卡片會顯示所選期間的執行次數和總執行時間，詳情見<.localized_link href="/guides/features/cache/bazel-cache#running-actions-and-usage">執行動作和使用量</.localized_link>。在 2.19.0 之後的 Struo 版本中，每個遙距動作都會標明其所屬的 Struo 運行，因此該頁面也會繪製佇列和執行時間圖表，並列出運行及其遙距動作、結果和計時，優先顯示正在運行的運行。運行會在**建置運行**中開啟其頁面。來自較舊用戶端的運行，以及從遙距快取回應的動作，不會計入其中。目前正在運行和排隊的遙距動作可透過 `get_remote_execution_activity` MCP 工具及其 REST 端點取得。兩者皆來自執行服務，而非工作節點通道。

參閱[Struo 的遙距執行指南](https://struo.run/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers)以了解佇列、驗證刷新和快取端點覆蓋。遵循<.localized_link href="/guides/features/build-insights/struo">Struo 建置洞察</.localized_link>以檢視產生的運行。
