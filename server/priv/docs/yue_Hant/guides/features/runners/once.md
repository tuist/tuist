---
{
  "title": "Once 遠端執行",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "在 Tuist 的 Linux 遠端執行工作節點上，執行符合條件的 Once 圖表指令動作。"
}
---
# Once 遠端執行 {#once-remote-execution}

共用快取可以避免重複其他機器已經完成的工作。遠端執行亦會將符合條件的快取未命中工作從你的電腦移走：Once 會在 Tuist 的一次性 Linux 工作節點上排程圖表指令動作，並透過同一個專案快取擷取其輸出。

> [!NOTE]
> 遠端執行目前只限邀請使用。[聯絡我們](mailto:contact@tuist.dev)以申請帳戶存取權限。

> [!IMPORTANT]
> **必要條件**
>
> - 一個已啟用遠端執行且具備可用執行容量的 Tuist 帳戶。
> - 支援 Tuist 遠端執行的 Once 版本。
> - 相容的伺服器，需公告工作節點映像、快取端點、並行度以及絕對執行目錄。省略目錄的伺服器與目前的 Once 用戶端不相容；Once 會在上傳工作前停止。
> - 可在公告的工作節點映像內於 `linux/amd64` 上執行的指令與工具鏈。

這只會執行圖表動作，而非整個 CI 工作。設定 Once 並不會安裝 GitHub 或 GitLab 工作流程協調器。

## 設定 {#setup}

完成<.localized_link href="/guides/get-started/once-project">開始使用 Once</.localized_link>。為快取與執行選擇相同的 Tuist 提供者，並鎖定服務所公告的工作節點映像：

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

使用可讀寫專案快取的憑證進行驗證，然後請求遠端執行：

```bash
once build --remote MyTarget
```

將目標與映像標籤替換為你自己的值。Once 會在上傳工作前檢查公告的映像、執行目錄、快取目的地及帳戶容量。快取與執行必須指向同一個專案。

## 為工作節點準備動作 {#prepare-actions-for-workers}

- 宣告輸入與輸出。輸出必須保留在動作的作業目錄之下。
- 在工作節點映像內解析工具，而非在發起電腦上使用絕對路徑。
- 使用可安全重複執行的動作：工作節點失敗或服務重新啟動可能會導致再次執行。
- 將逾時時間控制在服務的十分鐘動作限制內。不支援的需求（包括網路拒絕）會直接失敗，而不會靜默地在本地執行。

Once 會遵守帳戶公告的動作並行度，並在服務佇列滿載時退避。變更映像會將組建設定與快取結果分開，防止在不相容的工作節點映像之間重複使用。

## 檢視遠端執行 {#inspect-remote-execution}

專案側邊欄有一個**遠端執行**頁面。其**分析**卡片會顯示所選期間的執行次數與總執行時間，詳情請參閱<.localized_link href="/guides/features/cache/bazel-cache#running-actions-and-usage">執行動作與用量</.localized_link>。Once 的執行遙測目前尚未區分遠端執行與本地動作，因此該頁面沒有每次執行的遠端計時或正在執行的執行紀錄。頁面會說明此差距，並連結至**建構執行**以查看記錄的動作詳細資料。目前正在執行和佇列中的遠端動作可透過`get_remote_execution_activity` MCP 工具及其 REST 端點取得。兩者皆來自執行服務，而非工作節點通道。

請參閱[Once 的遠端執行指南](https://buildonce.dev/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers)以了解佇列、驗證刷新及快取端點覆寫。 follow <.localized_link href="/guides/features/build-insights/once">Once 建構洞察</.localized_link>以檢視產生的執行紀錄。
