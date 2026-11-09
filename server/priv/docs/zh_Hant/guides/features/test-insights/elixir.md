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
> **必要條件**
>
> - 完成<.localized_link href="/guides/get-started/elixir-project">Elixir 入門指南</.localized_link>

## 回報你的測試執行 {#report-your-test-runs}

共用設定會安裝測試整合。繼續使用 `mix test`，並保持相同的參數、輸出與結束碼：

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist 會在執行結束後回報；不需要額外的測試別名。

你可以在 Tuist 儀表板中存取測試洞察，並觀察其隨時間的變化：

![Phoenix 應用程式的測試儀表板](/images/guides/features/elixir/tests-dashboard.png)

## 追蹤內容 {#what-is-tracked}

該套件會收集 ExUnit 的結果，包括：
- 個別測試的通過/失敗狀態與耗時
- 每個測試所屬的模組與 `describe` 區塊
- 每個失敗的訊息與位置
- 跨多次執行的不穩定測試偵測
- 分支與提交，以及在持續整合環境中的提供者與執行
- 在持續整合環境中，檢出的 [Git 歷史記錄](#git-history)

文件測試會像其他測試一樣被回報。使用 `--cover` 時，也會上傳該次執行的行覆蓋率：請參閱 <.localized_link href="/guides/features/test-code-coverage/elixir">Elixir 程式碼覆蓋率</.localized_link>。

> [!NOTE]
> 套件透過一個 ExUnit 格式器進行回報，並將其加入你已使用的格式器清單中。若你在命令列上傳入 `--formatter`，Mix 會取代整個清單，導致該次執行不會被回報，且任務會發出警告。

### Git 歷史記錄 {#git-history}

在持續整合環境中，套件也會上傳檢出的提交歷史記錄：提交 SHA、其父提交、提交日期，以及該次執行與其拉取請求基礎分支所在的分支。不會上傳檔案內容、提交訊息或作者資訊。這能讓 Tuist 知道哪些提交已合併至你的預設分支，例如由合併佇列測試過的提交。套件會讀取檢出中已有的歷史記錄；若檢出中沒有基礎分支，則會向遠端查詢其最新提交（`git ls-remote`）。在非程式碼覆蓋率（`--cover`）的情況下，它不會抓取歷史記錄。

| 變數 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不會讀取或上傳任何 Git 歷史記錄。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 僅讀取檢出內容，不會聯絡遠端。 |

## 疑難排解 {#troubleshooting}

回報絕不會改變你的測試結果：若無法發送回報，執行會照常結束，且不會列印任何訊息。若要查看為何未發送回報，請設定 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix test
```
