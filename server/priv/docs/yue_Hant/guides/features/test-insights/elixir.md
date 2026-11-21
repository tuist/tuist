---
{
  "title": "Elixir 測試洞察",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板追蹤你嘅 Elixir 專案測試，以監察測試表現。"
}
---
# Elixir 測試洞察 {#elixir-test-insights}

Tuist 嘅 Hex 套件會喺每次測試執行之後上傳你 Elixir 專案嘅測試結果，令你可以直接喺 Tuist 儀表板查看測試表現同不穩定測試。

> [!IMPORTANT]
> **要求**
>
> - 完成<.localized_link href="/guides/get-started/elixir-project">Elixir 入門</.localized_link>

## 回報你嘅測試執行 {#report-your-test-runs}

共用設定會安裝測試整合。繼續使用 `mix test`，參數、輸出同退出碼都保持不變：

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist 會喺測試執行完畢時作出匯報；無需額外嘅測試別名。

你可以喺 Tuist 儀表板存取測試洞察，並觀察佢哋隨時間嘅變化：

![Phoenix 應用程式嘅測試儀表板](/images/guides/features/elixir/tests-dashboard.png)

## 追蹤內容 {#what-is-tracked}

套件會收集 ExUnit 嘅結果，包括：
- 個別測試嘅通過/失敗狀態同持續時間
- 每個測試所屬嘅模組同 `describe` 區塊
- 每個失敗嘅訊息同位置
- 跨多次執行檢測不穩定測試
- 分支同提交，以及喺持續整合環境入面嘅供應商同執行
- 喺持續整合環境入面，檢出嘅[Git 歷史](#git-history)

文檔測試會好似其他測試一樣被報告。使用 `--cover` 時，執行嘅行覆蓋率亦會上傳：請參閱 <.localized_link href="/guides/features/test-code-coverage/elixir">Elixir 代碼覆蓋率</.localized_link>。

> [!NOTE]
> 套件透過一個 ExUnit 格式化器進行報告，該格式化器會添加到你已經使用嘅格式化器旁邊。如果你喺命令行傳遞 `--formatter`，Mix 會替換整個列表，因此執行不會被報告，任務會向你發出警告。

### Git 歷史 {#git-history}

喺持續整合環境入面，套件亦會上傳檢出嘅提交歷史：提交 SHA、它們嘅父提交、提交日期，以及執行同其拉取請求基礎分支所處嘅分支。不會上傳任何文件內容、提交訊息或作者。這讓 Tuist 知道哪些提交已合併到你嘅默認分支，例如合併隊列測試過嘅提交。套件會讀取檢出已經擁有嘅歷史，如果檢出沒有基礎分支，則向遠程請求其最新提交 (`git ls-remote`)。除代碼覆蓋率 (`--cover`) 外，它不會獲取歷史。使用代碼覆蓋率時，淺層檢出會被加深（不包含文件內容），以找出拉取請求從何處分支出來，並喺持續整合環境入面到達 Tuist 已經擁有嘅提交，因此提交永遠不會喺沒有其父提交嘅情況下被上傳。

| 變量 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 不會讀取或上傳任何 Git 歷史。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 只讀取檢出，唔會聯繫遠程。 |

## 疑難排解 {#troubleshooting}

報告永遠不會改變你測試嘅結果：如果報告無法發送，執行會照常退出且不會打印任何內容。要查看報告為何未發送，請設置 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix test
```
