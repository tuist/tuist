---
{
  "title": "一次性遠端執行",
  "titleTemplate": ":title · Runners · 功能 · 指南 · Tuist",
  "description": "在 Tuist 的 Linux 遠端執行工作節點上，執行符合資格的一次性圖形指令動作。"
}
---
# Once 遠端執行 {#once-remote-execution}

共享快取可避免重複其他機器已完成的工作。遠端執行亦會將符合條件的快取未命中工作移出你的電腦：Once 會在 Tuist 的一次性 Linux 工作節點上排程圖形指令動作，並透過同一個專案快取擷取其輸出。

> [!NOTE]
> 遠端執行目前僅限邀請使用。[聯絡我們](mailto:contact@tuist.dev)以申請帳戶存取權限。

> [!IMPORTANT]
> **需求**
>
> - 已啟用遠端執行且具備可用執行容量的 Tuist 帳戶。
> - 支援 Tuist 遠端執行的 Once 版本。
> - 相容的伺服器，需宣告工作節點映像、快取端點、並行度及絕對執行目錄。省略目錄的伺服器與目前的 Once 用戶端不相容；Once 會在上傳工作前停止。
> - 可在宣告的工作節點映像內於 `linux/amd64` 上執行的指令與工具鏈。

這會執行圖形動作，而非整個 CI 工作。設定 Once 並不會安裝 GitHub 或 GitLab 工作流程協調器。

## 設定 {#setup}

完成<.localized_link href="/guides/get-started/once-project">開始使用 Once</.localized_link>。為快取與執行選擇相同的 Tuist 提供者，並鎖定服務所宣告的工作節點映像：

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

使用具有讀寫專案快取權限的憑證進行驗證，然後請求遠端執行：

```bash
once build --remote MyTarget
```

將目標與映像標籤替換為你自己的值。Once 會在上傳工作前檢查宣告的映像、執行目錄、快取目的地及帳戶容量。快取與執行必須指向同一個專案。

## 為工作節點準備動作 {#prepare-actions-for-workers}

- 宣告輸入與輸出。輸出必須保留在動作的作業目錄之下。
- 在工作節點映像內解析工具，而非在發起電腦上使用絕對路徑。
- 使用可安全重複執行的動作：工作節點失敗或服務重新啟動可能會導致再次執行。
- 將逾時時間控制在服務的十分鐘動作限制內。不支援的需求（包括網路拒絕）會失敗，而不會靜默地在本地執行。

Once 會遵循帳戶宣告的動作並行度，並在服務佇列滿載時退避。變更映像會分隔組建設定與快取結果，防止在不相容的工作節點映像之間重複使用。

## 檢視遠端執行 {#inspect-remote-execution}

專案側邊欄有一個**遠端執行**頁面，但 Once 執行遙測尚未區分遠端執行與本機動作。該頁面說明此差距，並連結至**建構執行**以查看記錄的動作詳情；它不會從工作節點通道推斷遠端活動，也不會將這些動作顯示為遠端用量。

參閱[Once 遠端執行指南](https://buildonce.dev/docs/guide/infrastructure/tuist#run-actions-on-tuist-workers)以了解佇列、驗證刷新及快取端點覆寫。跟隨<.localized_link href="/guides/features/build-insights/once">Once 建構洞察</.localized_link>來檢視產生的執行結果。
