---
{
  "title": "Elixir Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track the tests of your Elixir project in the Tuist dashboard to monitor test performance."
}
---
# Elixir 測試洞察 {#elixir-test-insights}

Tuist 的 Hex 套件會在每次測試運行後上傳你的 Elixir 專案測試結果，讓你能直接在 Tuist 儀表板中查看測試效能和不穩定測試。

> [!IMPORTANT] REQUIREMENTS
> - 完成 <.localized_link href="/guides/get-started/elixir-project">開始使用 Elixir</.localized_link>

## 報告你的測試運行 {#report-your-test-runs}

共享設定會安裝測試整合。繼續使用 `mix test`，參數、輸出和退出碼保持不變：

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist 會在運行結束時報告結果；無需額外的測試別名。

你可以在 Tuist 儀表板中查看測試洞察，並觀察其隨時間的變化：

![Phoenix 應用程式的測試儀表板](/images/guides/features/elixir/tests-dashboard.png)

## 追蹤內容 {#what-is-tracked}

套件會收集 ExUnit 的結果，包括：
- 個別測試的通過/失敗狀態和持續時間
- 每個測試所屬的模組和 `describe` 區塊
- 每次失敗的訊息和位置
- 跨運行的不穩定測試檢測
- 分支和提交，以及在持續整合中的提供者和運行
- 在持續整合中，檢出的 [Git 歷史記錄](#git-history)

Doctests 會像其他測試一樣被報告。使用 `--cover` 時，也會上傳運行的行覆蓋率：請參閱 <.localized_link href="/guides/features/test-code-coverage/elixir">Elixir 代碼覆蓋率</.localized_link>。

> [!NOTE]
> 套件透過一個 ExUnit 格式化器進行報告，該格式化器會添加到你已使用的格式化器旁邊。如果你在命令行傳遞 `--formatter`，Mix 會替換整個列表，導致運行未被報告，任務會對此發出警告。

### Git 歷史記錄 {#git-history}

在持續整合中，套件還會上傳檢出的提交歷史記錄：提交 SHA、其父節點、提交日期，以及運行和其拉取請求基礎分支所在的分支。不會上傳文件內容、提交訊息或作者。這能讓 Tuist 知道哪些提交已合併到你的默認分支，例如合併隊列測試過的提交。套件會讀取检出已有的歷史記錄，當检出沒有基礎分支時，會向遠端請求其最新提交 (`git ls-remote`)。除了代碼覆蓋率 (`--cover`) 外，它不會獲取歷史記錄。

| 變量 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不讀取或上傳任何 Git 歷史記錄。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 僅讀取检出，不聯繫遠端。 |

## 疑難排解 {#troubleshooting}

報告永遠不會改變你的測試結果：如果無法發送報告，運行會照常退出且不會打印任何內容。要查看報告未發送的原因，請設置 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix test
```
