---
{
  "title": "Elixir Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track the tests of your Elixir project in the Tuist dashboard to monitor test performance."
}
---
# Elixir 測試洞察 {#elixir-test-insights}

Tuist 的 Hex 套件會在每次測試執行後上傳你的 Elixir 專案測試結果，讓你能直接在 Tuist 儀表板中查看測試效能和不穩定測試。

> [!IMPORTANT] REQUIREMENTS
> - 完成 <.localized_link href="/guides/get-started/elixir-project">開始使用 Elixir</.localized_link>

## 回報你的測試執行 {#report-your-test-runs}

共用設定會安裝測試整合。繼續使用 `mix test`，參數、輸出和結束碼維持不變：

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist 會在執行結束時回報；不需要額外的測試別名。

你可以在 Tuist 儀表板中存取測試洞察，並觀察其隨時間的變化：

![Phoenix 應用程式的測試儀表板](/images/guides/features/elixir/tests-dashboard.png)

## 追蹤內容 {#what-is-tracked}

套件會收集 ExUnit 的結果，包括：
- 個別測試的通過/失敗狀態和持續時間
- 每個測試所屬的模組和 `describe` 區塊
- 每次失敗的訊息和位置
- 跨多次執行偵測不穩定測試
- 分支與提交，以及在持續整合中的提供者與執行
- 在持續整合中，檢出的[Git 歷史記錄](#git-history)

Doctests 會像其他測試一樣被報告。

> [!NOTE]
> 套件會透過一個 ExUnit formatter 進行報告，並將其添加到你已使用的 formatter 旁邊。如果你在命令列中傳遞 `--formatter`，Mix 會替換整個清單，導致該次執行不會被報告，且任務會向你發出警告。

### Git 歷史記錄 {#git-history}

在持續整合中，套件亦會上傳檢出（checkout）的提交歷史：提交 SHA、其父提交、提交日期，以及執行作業與其拉取請求基礎分支所在的分支。不會上傳任何檔案內容、提交訊息或作者資訊。這讓 Tuist 知道哪些提交已合併至你的預設分支，例如由合併佇列測試過的提交。套件會讀取檢出中已有的歷史記錄；若檢出沒有基礎分支，則會向遠端查詢其最新提交（`git ls-remote`）。除程式碼涵蓋率（`--cover`）外，它不會擷取歷史記錄。

| 變數 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不會讀取或上傳任何 Git 歷史記錄。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 僅讀取檢出內容，不會聯絡遠端。 |

## 疑難排解 {#troubleshooting}

回報絕不會改變你的測試結果：如果無法傳送報告，執行作業會照常結束，且不會列印任何內容。若要查看報告未傳送的原因，請設定 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix test
```
