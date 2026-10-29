---
{
  "title": "Elixir Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track the tests of your Elixir project in the Tuist dashboard to monitor test performance."
}
---
# Elixir 測試洞察 {#elixir-test-insights}

Tuist 的 Hex 套件會在每次測試執行後上傳您 Elixir 專案的測試結果，讓您在 Tuist 儀表板中直接掌握測試效能與不穩定測試。

> [!IMPORTANT] REQUIREMENTS
> - 完成 <.localized_link href="/guides/get-started/elixir-project">開始使用 Elixir</.localized_link>

## 回報您的測試執行 {#report-your-test-runs}

共享設定會安裝測試整合。繼續使用 `mix test`，並保持相同的參數、輸出與結束碼：

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist 會在測試執行完畢時回報；無需額外的測試別名。

您可以在 Tuist 儀表板中存取測試洞察，並觀察其隨時間的變化：

![Phoenix 應用程式的測試儀表板](/images/guides/features/elixir/tests-dashboard.png)

## 追蹤內容 {#what-is-tracked}

此套件會收集 ExUnit 的結果，包括：
- 個別測試的通過/失敗狀態與持續時間
- 每個測試所屬的模組與 `describe` 區塊
- 每次失敗的訊息與位置
- 跨多次執行偵測不穩定測試
- 分支與提交，以及在持續整合中的提供者與執行
- 在持續整合中，檢出的[Git 歷史記錄](#git-history)

文件測試會像其他測試一樣被回報。使用 `--cover` 時，也會上傳執行的行覆蓋率：請參閱 <.localized_link href="/guides/features/test-code-coverage/elixir">Elixir 程式碼覆蓋率</.localized_link>。

> [!NOTE]
> 套件透過一個 ExUnit 格式化器進行回報，該格式化器會附加在你已使用的格式化器旁邊。如果你在命令列上傳入 `--formatter`，Mix 會替換整個清單，導致執行不會被回報，且任務會向你發出警告。

### Git 歷史記錄 {#git-history}

在持續整合中，套件也會上傳檢出的提交歷史記錄：提交的 SHA、其父提交、提交日期，以及執行與其拉取請求基礎分支所在的分支。不會上傳檔案內容、提交訊息或作者資訊。這能讓 Tuist 知道哪些提交已合併到你的預設分支，例如合併佇列所測試的提交。套件會讀取檢出時已有的歷史記錄，當檢出沒有基礎分支時，會向遠端查詢其最新提交（`git ls-remote`）。除了程式碼覆蓋率（`--cover`）之外，它不會抓取歷史記錄。

| 變數 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不會讀取或上傳任何 Git 歷史記錄。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 僅讀取檢出內容，不會聯絡遠端。 |

## 疑難排解 {#troubleshooting}

回報永遠不會改變你的測試結果：如果無法發送報告，執行會照常結束且不會列印任何內容。若要查看為何未發送報告，請設定 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix test
```
