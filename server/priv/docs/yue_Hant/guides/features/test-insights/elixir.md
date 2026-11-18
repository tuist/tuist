---
{
  "title": "Elixir 測試洞察",
  "titleTemplate": ":title · 測試洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 儀表板追蹤 Elixir 專案嘅測試，以監察測試效能。"
}
---
# Elixir 測試洞察 {#elixir-test-insights}

Tuist 嘅 Hex 套件會喺每次測試執行之後上載你 Elixir 專案嘅測試結果，讓你直接喺 Tuist 儀表板入面了解測試表現同不穩定測試。

> [!IMPORTANT]
> **要求**
>
> - 完成 <.localized_link href="/guides/get-started/elixir-project">Elixir 入門</.localized_link>

## 回報你嘅測試執行 {#report-your-test-runs}

共用設定會安裝測試整合。繼續使用 `mix test`，參數、輸出同退出碼都一樣：

```bash
mix test test/my_app_test.exs:12 --trace
```

Tuist 會喺執行完畢時回報；唔需要額外嘅測試別名。

你可以喺 Tuist 儀表板存取你嘅測試洞察，並觀察佢哋隨時間嘅變化：

![Phoenix 應用程式嘅測試儀表板](/images/guides/features/elixir/tests-dashboard.png)

## 追蹤內容 {#what-is-tracked}

套件會收集 ExUnit 嘅結果，包括：
- 個別測試嘅通過/失敗狀態同持續時間
- 每個測試所屬嘅模組同 `describe` 區塊
- 每次失敗嘅訊息同位置
- 跨執行偵測不穩定測試
- 分支同提交，以及喺持續整合環境下嘅提供者同執行
- 喺持續整合環境下，checkout 嘅 [Git 歷史](#git-history)

Doctest 會好似其他測試一樣被回報。使用 `--cover` 時，亦會上載執行嘅行覆蓋率：請參閱 <.localized_link href="/guides/features/test-code-coverage/elixir">Elixir 代碼覆蓋率</.localized_link>。

> [!NOTE]
> 套件透過一個 ExUnit 格式器進行回報，該格式器會添加到你已經使用嘅格式器旁邊。如果你喺命令行傳遞 `--formatter`，Mix 會替換整個列表，導致執行唔會被回報，任務會就此發出警告。

### Git 歷史 {#git-history}

喺持續整合環境下，套件亦會上載 checkout 嘅提交歷史：提交 SHA、其父提交、提交日期，以及執行同其拉取請求基礎分支所處嘅分支。唔會上載文件內容、提交訊息或作者。呢個資訊讓 Tuist 知道邊啲提交已合併到你嘅預設分支，例如合併隊列測試過嘅提交。套件會讀取 checkout 已有嘅歷史，如果 checkout 冇基礎分支，就會向遠端查詢其最新提交（`git ls-remote`）。除咗代碼覆蓋率（`--cover`）之外，佢唔會抓取歷史。使用代碼覆蓋率時，淺層 checkout 會被加深（唔包含文件內容），以搵出拉取請求從邊度分支出來，並喺持續整合環境下到達 Tuist 已有嘅提交，確保提交永遠唔會喺冇父提交嘅情況下上載。

| 變數 | 效果 |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | 唔會讀取或上載任何 Git 歷史。 |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | 只讀取 checkout，唔會聯絡遠端。 |

## 疑難排解 {#troubleshooting}

回報永遠唔會改變你測試嘅結果：如果報告無法發送，執行會照常退出，亦唔會打印任何內容。要查看報告為何未被發送，請設置 `TUIST_DEBUG=1`：

```bash
TUIST_DEBUG=1 mix test
```
