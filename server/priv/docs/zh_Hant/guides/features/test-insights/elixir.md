---
{
  "title": "Elixir 測試洞察",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板中追蹤 Elixir 專案的測試，以監控測試效能。"
}
---
# Elixir 測試洞察 {#elixir-test-insights}

Tuist 的 Hex 套件會在每次測試執行後上傳你的 Elixir 專案測試結果，讓你能直接在 Tuist 儀表板中檢視測試效能與不穩定測試。

> [!IMPORTANT]
> **必要條件**
>
> - 完成<.localized_link href="/guides/get-started/elixir-project">Elixir 入門指南</.localized_link>

## 回報你的測試執行 {#report-your-test-runs}

共用設定會安裝測試整合。繼續使用 `mix test`，參數、輸出與結束碼皆維持不變：

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist 會在測試執行完畢時回報；無需額外設定測試別名。

你可以在 Tuist 儀表板中存取測試洞察，並觀察其隨時間的變化：

![Phoenix 應用程式的測試儀表板](/images/guides/features/elixir/tests-dashboard.png)

## 追蹤項目 {#what-is-tracked}

該套件會收集 ExUnit 的結果，包括：
- 個別測試的通過/失敗狀態與耗時
- 每個測試所屬的模組與 `describe` 區塊
- 每次失敗的訊息與位置
- 跨多次測試執行的不穩定測試偵測
- 分支與提交，以及在持續整合環境中的提供者與執行
- 在持續整合環境中，檢出版本的[Git 歷史記錄](#git-history)

文件測試會像其他測試一樣被回報。使用`--cover`時，也會上傳該次執行的行覆蓋率：請參閱<.localized_link href="/guides/features/test-code-coverage/elixir">Elixir 程式碼覆蓋率</.localized_link>。

> [!NOTE]
> 此套件透過一個 ExUnit 格式器進行回報，該格式器會附加在你已使用的格式器旁邊。如果你在命令列上傳入`--formatter`，Mix 會取代整個清單，導致該次執行不會被回報，且任務會向你發出警告。

### Git 歷史記錄{#git-history}

在持續整合環境中，此套件也會上傳檢出版本的提交歷史記錄：提交的 SHA、其父提交、提交日期，以及該次執行與其拉取請求基礎分支所在的分支。不會上傳任何檔案內容、提交訊息或作者資訊。這能讓 Tuist 知道哪些提交已合併到你的預設分支，例如合併佇列所測試的提交。此套件會讀取檢出版本中已有的歷史記錄；當檢出版本不包含基礎分支時，它會向遠端查詢最新的提交（`git ls-remote`）。在非程式碼覆蓋率（`--cover`）的情況下，它不會抓取歷史記錄。在使用程式碼覆蓋率時，淺層檢出會被深化（不包含檔案內容），以找出拉取請求的分叉點，並在持續整合環境中取得 Tuist 已擁有的提交，確保絕不會上傳沒有父提交的提交。

| 變數 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不會讀取或上傳任何 Git 歷史記錄。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 僅讀取已檢出的內容，不與遠端伺服器聯絡。 |
| `TUIST_GIT_BRANCH=<branch>` | 指定執行所在的分支名稱，優先於 CI 提供者與已檢出內容所提供的資訊。在 Tuist 無法識別、且會檢出特定提交而非分支的 CI 系統上設定此變數；否則這些系統的執行將沒有分支資訊。 |

## 疑難排解 {#troubleshooting}

回報功能絕不會改變測試結果：若無法傳送報告，執行仍會照常結束，且不會印出任何訊息。若要查看報告未傳送的原因，請設定 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix test
```
