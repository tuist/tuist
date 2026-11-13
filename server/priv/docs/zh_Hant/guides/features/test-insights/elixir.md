---
{
  "title": "Elixir 測試洞察",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板中追蹤 Elixir 專案的測試，以監控測試效能。"
}
---
# Elixir 測試洞察 {#elixir-test-insights}

Tuist 的 Hex 套件會在每次測試執行後上傳你的 Elixir 專案測試結果，讓你能直接在 Tuist 儀表板中查看測試效能與不穩定測試。

> [!IMPORTANT]
> **需求**
>
> - 完成<.localized_link href="/guides/get-started/elixir-project">Elixir 入門指南</.localized_link>

## 回報你的測試執行 {#report-your-test-runs}

共用設定會安裝測試整合。繼續使用 `mix test`，參數、輸出與結束代碼皆相同：

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist 會在測試執行結束後回報；無需額外的測試別名。

你可以在 Tuist 儀表板中存取測試洞察，並觀察其隨時間的變化：

![Phoenix 應用程式的測試儀表板](/images/guides/features/elixir/tests-dashboard.png)

## 追蹤內容 {#what-is-tracked}

此套件會收集 ExUnit 的結果，包括：
- 個別測試的通過／失敗狀態與耗時
- 每個測試所屬的模組與 `describe` 區塊
- 每次失敗的訊息與位置
- 跨多次執行的不穩定測試偵測
- 分支與提交，以及在持續整合中的提供者與執行
- 在持續整合中，檢出版本的[Git 歷史記錄](#git-history)

文件測試會像其他測試一樣被回報。使用 `--cover` 時，也會上傳該次執行的行覆蓋率：請參閱 <.localized_link href="/guides/features/test-code-coverage/elixir">Elixir 程式碼覆蓋率</.localized_link>。

> [!NOTE]
> 套件透過它附加在你已使用的格式化器旁的 ExUnit 格式化器進行回報。若你在命令列上傳入 `--formatter`，Mix 會取代整個清單，導致該次執行不會被回報，且任務會向你發出警告。

### Git 歷史記錄 {#git-history}

在持續整合中，套件也會上傳檢出版本的提交歷史記錄：提交的 SHA、其父提交、提交日期，以及該次執行與其拉取請求基礎分支所在的分支。不會上傳檔案內容、提交訊息或作者資訊。這讓 Tuist 能得知哪些提交已合併至你的預設分支，例如合併佇列所測試的提交。套件會讀取檢出版本已有的歷史記錄；若檢出版本缺少基礎分支，則會向遠端查詢其最新提交（`git ls-remote`）。在非程式碼覆蓋率（`--cover`）模式下，不會抓取歷史記錄。在使用程式碼覆蓋率時，會在不包含檔案內容的情況下加深淺層檢出，以找出拉取請求的分叉點，並在持續整合中取得 Tuist 已拥有的提交，確保每個提交上傳時都包含其父提交。

| 變數 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不會讀取或上傳任何 Git 歷史記錄。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 僅讀取檢出版本，不會聯絡遠端。 |

## 疑難排解 {#troubleshooting}

回報作業永遠不會改變測試結果：若無法傳送回報，執行會照常結束，且不會印出任何訊息。若要查看為何未傳送回報，請設定 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix test
```
