---
{
  "title": "Elixir 測試洞察",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板追蹤 Elixir 專案的測試，以監控測試效能。"
}
---
# Elixir 測試洞察 {#elixir-test-insights}

Tuist 嘅 Hex 套件會喺每次測試執行之後上載你 Elixir 專案嘅測試結果，令你可以直接喺 Tuist 儀表板查看測試表現同不穩定測試。

> [!IMPORTANT]
> **必要條件**
>
> - 完成 <.localized_link href="/guides/get-started/elixir-project">開始使用 Elixir</.localized_link>

## 報告你嘅測試執行 {#report-your-test-runs}

共用設定會安裝測試整合。繼續使用 `mix test`，參數、輸出同退出碼都一樣：

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist 會喺執行完畢時報告；唔需要額外嘅測試別名。

你可以喺 Tuist 儀表板存取你嘅測試洞察，並觀察佢哋隨時間嘅變化：

![Phoenix 應用程式嘅測試儀表板](/images/guides/features/elixir/tests-dashboard.png)

## 追蹤內容 {#what-is-tracked}

套件會收集 ExUnit 嘅結果，包括：
- 個別測試嘅通過/失敗狀態同持續時間
- 每個測試所屬嘅模組同 `describe` 區塊
- 每次失敗嘅訊息同位置
- 跨執行偵測不穩定測試
- 分支同提交，以及喺持續整合環境下嘅提供者同執行
- 喺持續整合環境下，檢出嘅 [Git 歷史](#git-history)

文件測試會好似其他測試咁報告。使用 `--cover` 時，亦會上載執行嘅行覆蓋率：請參閱 <.localized_link href="/guides/features/test-code-coverage/elixir">Elixir 代碼覆蓋率</.localized_link>。

> [!NOTE]
> 套件透過一個 ExUnit 格式器進行報告，該格式器會添加到你已經使用嘅格式器旁邊。如果你喺命令行傳遞 `--formatter`，Mix 會替換整個列表，導致執行唔會被報告，任務會向你發出警告。

### Git 歷史 {#git-history}

喺持續整合環境下，套件亦會上載檢出嘅提交歷史：提交 SHA、其父提交、提交日期，以及執行及其拉取請求基礎分支所處嘅分支。唔會上載檔案內容、提交訊息或作者。呢樣資料會告訴 Tuist 哪些提交已合併到你嘅預設分支，例如合併隊列測試過嘅提交。套件會讀取檢出已有嘅歷史，如果檢出冇基礎分支，就會向遠端查詢其最新提交（`git ls-remote`）。除咗代碼覆蓋率（`--cover`）之外，佢唔會獲取歷史。使用代碼覆蓋率時，淺層檢出會加深（唔包含檔案內容），以找出拉取請求嘅分支點，並喺持續整合環境下到達 Tuist 已有嘅提交，確保提交永遠唔會喺冇父提交嘅情況下上載。

| 變量 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 唔會讀取或上載任何 Git 歷史。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 只讀取檢出，唔會聯絡遠端。 |
| `TUIST_GIT_BRANCH=<branch>` | 命名執行嘅分支，優先於 CI 提供者同檢出嘅分支。喺 Tuist 唔識別嘅 CI 系統上設置，呢啲系統檢出嘅係提交而非分支，否則執行會冇分支。 |

## 疑難排解 {#troubleshooting}

報告永遠唔會改變你測試嘅結果：如果報告無法發送，執行會照常退出，亦唔會打印任何內容。要查看報告為何未發送，請設置 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix test
```
